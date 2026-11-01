// Runs the translated game on a PC with no screen or sound, and writes RAM at
// every NMI in the same format as the Mesen recording. tools/compare.py then
// finds the first difference.
//
//     out/host <rom> <trace-dir> <frames> <ram-out.bin> [step-log from to]
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hw.h"

static struct { int nmi, addr, val; } *pokes;  // the recording script's RAM writes
static int poke_count, poke_next;
static u8 *pad_reads;   // what the game read from $4016/7 in the recording
static long pad_read_count, pad_next;
static FILE *ram_out, *step_log, *apu_log;
void apu_log_line(FILE *f);
static int step_from, step_to;
static int nmi_count, nmi_limit;

u32 trap(u32 pc) {
  fprintf(stderr, "TRAP: untranslated code at $%04X, banks %02X %02X %02X, after NMI %d, cycle %u\n",
          pc, prg_map[0], prg_map[1], prg_map[2], nmi_count, cyc);
  exit(2);
}

// Set DUMP_FRAME to write the video state at that NMI, for tools/show_dump.py.
static int dump_frame = -1;
#define SAMPLES_PER_FRAME 304
// Set WAV to write the sound to a raw file of signed 8-bit samples.
static FILE *wav;

// Set SHOTS to a file of "frame name" lines and SHOT_DIR to a folder to get what the
// GBA would show at those frames. This is a small stand-in for its picture hardware.
u8 sim_io[0x400], sim_vram[0x18000], sim_pal[0x400], sim_oam[0x400];
static struct { int frame; char name[64]; } shots[4096];
static int shot_count, shot_next, video_on;
static const char *shot_dir;

// (A blank screen is black here too: its layers are all off and colour 0 is black.)
static u16 bg_pixel(int bg, int x, int y, int *solid) {
  u16 cnt = REG16(0x04000008 + bg * 2);
  int hofs = bg < 3 ? REG16(0x04000010 + bg * 4) & 511 : 0, vofs = bg < 3 ? REG16(0x04000012 + bg * 4) & 511 : 0;
  int px = (x + hofs) & 255, py = (y + vofs) & 255;
  u16 *map = (u16 *)(sim_vram + ((cnt >> 8) & 31) * 0x800);
  u16 e = map[(py >> 3) * 32 + (px >> 3)];
  const u8 *tile = sim_vram + ((cnt >> 2) & 3) * 0x4000 + (e & 1023) * 32;
  if (e & 0x400) px = 7 - (px & 7);
  if (e & 0x800) py = 7 - (py & 7);
  px &= 7; py &= 7;
  int c = (tile[py * 4 + (px >> 1)] >> ((px & 1) * 4)) & 15;
  *solid = c != 0;
  return ((u16 *)sim_pal)[(e >> 12) * 16 + c];
}

static void take_shot(const char *name) {
  static u16 fb[160][240];
  u16 disp = REG16(0x04000000);
  u16 back = ((u16 *)sim_pal)[0];
  for (int y = 0; y < 160; y++) {
    for (int x = 0; x < 240; x++) fb[y][x] = (disp & 0x80) ? 0x7FFF : back;
  }
  if (!(disp & 0x80)) {
    int w0 = disp & 0x2000, w1 = disp & 0x4000;
    int a0 = REG16(0x04000044) >> 8, a1 = REG16(0x04000044) & 255;
    int b0 = REG16(0x04000046) >> 8, b1 = REG16(0x04000046) & 255;
    u16 win_in = REG16(0x04000048), win_out = REG16(0x0400004A);
#define LAYERS(y) (w0 && (y) >= a0 && (y) < a1 ? win_in & 0xFF : w1 && (y) >= b0 && (y) < b1 ? win_in >> 8 : (w0 || w1) ? win_out : 0x1F)
    for (int prio = 3; prio >= 0; prio--) {
      for (int bg = 3; bg >= 0; bg--) {
        if (!(disp >> (8 + bg) & 1) || (REG16(0x04000008 + bg * 2) & 3) != prio) continue;
        for (int y = 0; y < 160; y++) {
          if (!(LAYERS(y) >> bg & 1)) continue;
          for (int x = 0; x < 240; x++) {
            int solid;
            u16 c = bg_pixel(bg, x, y, &solid);
            if (solid) fb[y][x] = c;
          }
        }
      }
      if (!(disp & 0x1000)) continue;
      for (int i = 127; i >= 0; i--) {
        u16 *o = (u16 *)sim_oam + i * 4;
        if ((o[0] & 0x300) == 0x200 || ((o[2] >> 10) & 3) != prio) continue;
        int tall = o[0] & 0x8000, h = tall ? 16 : 8;
        int ox = o[1] & 511, oy = o[0] & 255;
        if (ox >= 256) ox -= 512;
        if (oy >= 160) oy -= 256;
        for (int sy = 0; sy < h; sy++) {
          int y = oy + sy;
          if (y < 0 || y >= 160 || !(LAYERS(y) >> 4 & 1)) continue;
          int ty = (o[1] & 0x2000) ? h - 1 - sy : sy;
          const u8 *tile = sim_vram + 0x10000 + ((o[2] & 1023) + (ty >> 3)) * 32;
          for (int sx = 0; sx < 8; sx++) {
            int x = ox + sx;
            if (x < 0 || x >= 240) continue;
            int tx = (o[1] & 0x1000) ? 7 - sx : sx;
            int c = (tile[(ty & 7) * 4 + (tx >> 1)] >> ((tx & 1) * 4)) & 15;
            if (c) fb[y][x] = ((u16 *)sim_pal)[256 + (o[2] >> 12) * 16 + c];
          }
        }
      }
    }
  }
  char path[512];
  snprintf(path, sizeof path, "%s/%s.ppm", shot_dir, name);
  FILE *f = fopen(path, "wb");
  fprintf(f, "P6 240 160 255\n");
  for (int y = 0; y < 160; y++) {
    for (int x = 0; x < 240; x++) {
      u16 c = fb[y][x];
      fputc((c & 31) << 3, f); fputc(((c >> 5) & 31) << 3, f); fputc(((c >> 10) & 31) << 3, f);
    }
  }
  fclose(f);
}

static void video_host_init(void) {
  static u8 tiles[0x40000];
  for (int t = 0; t < 8192; t++) {
    for (int y = 0; y < 8; y++) {
      u8 lo = chr[t * 16 + y], hi = chr[t * 16 + 8 + y];
      u32 row = 0;
      for (int x = 0; x < 8; x++) row |= (u32)((lo >> (7 - x) & 1) | (hi >> (7 - x) & 1) << 1) << (x * 4);
      memcpy(tiles + t * 32 + y * 4, &row, 4);
    }
  }
  chr4 = tiles;
  video_init();
}

void plat_vblank(void) {
  // The game keeps NMIs running, so a long gap means it has gone wrong.
  static int last_nmi, frames_since;
  if (nmi_count != last_nmi) { last_nmi = nmi_count; frames_since = 0; }
  else if (++frames_since > 600) {
    fprintf(stderr, "HUNG after NMI %d, banks %02X %02X %02X\n", nmi_count, prg_map[0], prg_map[1], prg_map[2]);
    fflush(ram_out);
    exit(3);
  }
  static s8 unheard[SAMPLES_PER_FRAME];
  if (apu_log && !wav) apu_mix(unheard, SAMPLES_PER_FRAME);  // this is what ticks the envelopes
  if (video_on) {
    video_present();
    while (shot_next < shot_count && shots[shot_next].frame <= nmi_count + 1) {
      if (shots[shot_next].frame == nmi_count + 1) {
        take_shot(shots[shot_next].name);
        if (getenv("SPLITLOG")) { fprintf(stderr, "%s regions=%d", shots[shot_next].name, region_count); for (int i = 0; i < region_count; i++) fprintf(stderr, " line=%d t=%04X x=%d ctrl=%02X own=%d", regions[i].line, regions[i].t, regions[i].x, regions[i].ctrl, regions[i].own_row); fprintf(stderr, "\n"); }
      }
      shot_next++;
    }
  }
  if (wav) {
    static s8 buf[SAMPLES_PER_FRAME];
    apu_mix(buf, SAMPLES_PER_FRAME);
    fwrite(buf, 1, SAMPLES_PER_FRAME, wav);
  }
  if (nmi_count != dump_frame) return;
  FILE *f = fopen("out/video_dump.bin", "wb");
  fwrite(ciram, 1, 0x800, f); fwrite(palette, 1, 32, f); fwrite(oam, 1, 256, f);
  fwrite(top_chr, 1, 8, f); fwrite(chr_map, 1, 8, f);
  u8 m[10] = {top_t, top_t >> 8, top_x, top_ctrl, 0, 0, ppu_t, ppu_t >> 8, mirror_mode, ppu_mask};
  fwrite(m, 1, 10, f);
  fclose(f);
}

u8 plat_pad_read(u16 a) {
  return pad_next < pad_read_count ? pad_reads[pad_next++] : 0x40;
}

void plat_nmi(void) {
  if (apu_log) apu_log_line(apu_log);
  while (poke_next < poke_count && pokes[poke_next].nmi <= nmi_count + 1) {
    u16 a = pokes[poke_next].addr;
    if (a < 0x2000) ram[a & 0x7FF] = pokes[poke_next].val;
    poke_next++;
  }
  fwrite(ram, 1, sizeof ram, ram_out);
  fwrite(w6000, 1, 0x2000, ram_out);
  if (++nmi_count >= nmi_limit) {
    fclose(ram_out);
    if (wav) fclose(wav);
    if (apu_log) fclose(apu_log);
    fprintf(stderr, "ran %d NMIs, %u cycles, %ld pad reads\n", nmi_count, cyc, pad_next);
    exit(0);
  }
}

void plat_sync_missed(int nmi, u32 pc, u32 want) {
  static int reported;
  if (reported++ < 8)
    fprintf(stderr, "NMI %d: never reached the recording's place: at $%04X, wanted $%04X; A=%02X X=%02X Y=%02X S=%02X\n",
            nmi + 1, pc, want, A, X, Y, S);
}

void plat_step(u32 pc) {
  if (step_log && nmi_count >= step_from && nmi_count <= step_to)
    fprintf(step_log, "%04X %02X %02X %02X %02X\n", pc, A, X, Y, S);
}

int main(int argc, char **argv) {
  if (argc < 5) return 1;
  static u8 rom[0x60010];
  FILE *f = fopen(argv[1], "rb");
  if (!f || !fread(rom, 1, sizeof rom, f)) return 1;
  fclose(f);
  prg = rom + 16;
  chr = rom + 16 + 0x40000;

  char path[1024];
  snprintf(path, sizeof path, "%s/padreads.bin", argv[2]);
  f = fopen(path, "rb");
  if (!f) return 1;
  pad_reads = malloc(1 << 24);
  pad_read_count = fread(pad_reads, 1, 1 << 24, f);
  fclose(f);
  snprintf(path, sizeof path, "%s/pokes.txt", argv[2]);
  f = fopen(path, "r");
  pokes = malloc(sizeof *pokes * 100000);
  if (f) {
    while (fscanf(f, "%d %d %d", &pokes[poke_count].nmi, &pokes[poke_count].addr, &pokes[poke_count].val) == 3) poke_count++;
    fclose(f);
  }
  snprintf(path, sizeof path, "%s/poweron.bin", argv[2]);
  f = fopen(path, "rb");
  if (f) {
    static u8 on[0x2800];
    fread(on, 1, sizeof on, f);
    fclose(f);
    cpu_power_on(on);
  }
  nmi_limit = atoi(argv[3]);
  // Where the recording took each NMI: registers from cpu.txt, PC from the stack.
  snprintf(path, sizeof path, "%s/cpu.txt", argv[2]);
  f = fopen(path, "r");
  snprintf(path, sizeof path, "%s/ram.bin", argv[2]);
  FILE *recorded = fopen(path, "rb");
  if (f && recorded && !getenv("NO_SYNC")) {
    static nmi_sync_t table[300000];
    int n, a_, x_, y_, s_, p_;
    long cycles;
    while (nmi_sync_count < 300000 && fscanf(f, "%d %ld %d %d %d %d %d", &n, &cycles, &a_, &x_, &y_, &s_, &p_) == 7) {
      u8 pcs[2], low[32];
      fseek(recorded, (long)nmi_sync_count * 0x2800 + 0x100 + s_ + 2, SEEK_SET);
      if (fread(pcs, 1, 2, recorded) != 2) break;
      fseek(recorded, (long)nmi_sync_count * 0x2800, SEEK_SET);
      if (fread(low, 1, 32, recorded) != 32) break;
      nmi_sync_t *e = &table[nmi_sync_count++];
      e->pc = pcs[0] | pcs[1] << 8;
      e->scratch = scratch_sum(low);
      e->a = a_; e->x = x_; e->y = y_; e->s = s_;
    }
    nmi_sync = table;
  }
  if (f) fclose(f);
  if (recorded) fclose(recorded);
  ram_out = fopen(argv[4], "wb");
  if (argc > 7) {
    step_log = fopen(argv[5], "w");
    step_from = atoi(argv[6]);
    step_to = atoi(argv[7]);
  }
  if (getenv("DUMP_FRAME")) dump_frame = atoi(getenv("DUMP_FRAME"));
  apu_init(18157);
  if (getenv("APU_ONLY")) { extern int apu_only; apu_only = atoi(getenv("APU_ONLY")); }
  if (getenv("APU_LOG")) apu_log = fopen(getenv("APU_LOG"), "w");
  if (getenv("SHOTS") && getenv("SHOT_DIR")) {
    FILE *l = fopen(getenv("SHOTS"), "r");
    char line[128];
    while (l && fgets(line, sizeof line, l)) {
      if (sscanf(line, "%d %63s", &shots[shot_count].frame, shots[shot_count].name) == 2) shot_count++;
    }
    if (l) fclose(l);
    shot_dir = getenv("SHOT_DIR");
    video_on = 1;
    video_host_init();
  }
  if (getenv("WAV")) wav = fopen(getenv("WAV"), "wb");
  cpu_run();
  return 0;
}
