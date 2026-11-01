// Runs the translated game on a PC with no screen or sound, and writes RAM at
// every NMI in the same format as the Mesen recording. tools/compare.py then
// finds the first difference.
//
//     out/host <rom> <padreads.bin> <frames> <ram-out.bin> [step-log from to]
#include <stdio.h>
#include <stdlib.h>
#include "platform.h"

static u8 *pad_reads;   // what the game read from $4016/7 in the recording
static long pad_read_count, pad_next;
static FILE *ram_out, *step_log;
static int step_from, step_to;
static int nmi_count, nmi_limit;

u32 trap(u32 pc) {
  fprintf(stderr, "TRAP: untranslated code at $%04X, banks %02X %02X %02X, after NMI %d, cycle %u\n",
          pc, prg_map[0], prg_map[1], prg_map[2], nmi_count, cyc);
  exit(2);
}

// Set DUMP_FRAME to write the video state at that NMI, for tools/show_dump.py.
static int dump_frame = -1;
void plat_vblank(void) {
  if (nmi_count != dump_frame) return;
  FILE *f = fopen("out/video_dump.bin", "wb");
  fwrite(ciram, 1, 0x800, f); fwrite(palette, 1, 32, f); fwrite(oam, 1, 256, f);
  fwrite(top_chr, 1, 8, f); fwrite(chr_map, 1, 8, f);
  u8 m[10] = {top_t, top_t >> 8, top_x, top_ctrl, split_line & 255, split_line >> 8 & 1, ppu_t, ppu_t >> 8, mirror_mode, ppu_mask};
  fwrite(m, 1, 10, f);
  fclose(f);
}

u8 plat_pad_read(u16 a) {
  return pad_next < pad_read_count ? pad_reads[pad_next++] : 0x40;
}

void plat_nmi(void) {
  fwrite(ram, 1, sizeof ram, ram_out);
  fwrite(w6000, 1, 0x2000, ram_out);
  if (++nmi_count >= nmi_limit) {
    fclose(ram_out);
    fprintf(stderr, "ran %d NMIs, %u cycles, %ld pad reads\n", nmi_count, cyc, pad_next);
    exit(0);
  }
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

  f = fopen(argv[2], "rb");
  if (!f) return 1;
  pad_reads = malloc(1 << 24);
  pad_read_count = fread(pad_reads, 1, 1 << 24, f);
  fclose(f);
  nmi_limit = atoi(argv[3]);
  ram_out = fopen(argv[4], "wb");
  if (argc > 7) {
    step_log = fopen(argv[5], "w");
    step_from = atoi(argv[6]);
    step_to = atoi(argv[7]);
  }
  if (getenv("DUMP_FRAME")) dump_frame = atoi(getenv("DUMP_FRAME"));
  cpu_run();
  return 0;
}
