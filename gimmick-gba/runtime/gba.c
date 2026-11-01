// The game on the GBA. It runs one NES frame per GBA frame and draws at the end
// of each from the NES's nametables, OAM and palette.
//
// With REPLAY defined it plays back the recording instead of the buttons, checks
// RAM against tools/build_gba.py's table, and prints timing and the check's result
// to mGBA's debug log, which tools/run_gba.py reads.
#include "platform.h"

#define REG16(a) (*(volatile u16 *)(a))
#define REG32(a) (*(volatile u32 *)(a))
#define DISPCNT REG16(0x04000000)
#define DISPSTAT REG16(0x04000004)
#define VCOUNT REG16(0x04000006)
#define BG0CNT REG16(0x04000008)
#define BG1CNT REG16(0x0400000A)
#define BG0HOFS REG16(0x04000010)
#define BG0VOFS REG16(0x04000012)
#define BG1HOFS REG16(0x04000014)
#define BG1VOFS REG16(0x04000016)
#define DMA3SAD REG32(0x040000D4)
#define DMA3DAD REG32(0x040000D8)
#define DMA3CNT REG32(0x040000DC)
#define TM0CNT_L REG16(0x04000100)
#define TM0CNT_H REG16(0x04000102)
#define TM1CNT_L REG16(0x04000104)
#define TM1CNT_H REG16(0x04000106)
#define KEYINPUT REG16(0x04000130)
#define WAITCNT REG16(0x04000204)
#define WIN0H REG16(0x04000040)
#define WIN0V REG16(0x04000044)
#define WININ REG16(0x04000048)
#define WINOUT REG16(0x0400004A)
#define BG_PAL ((volatile u16 *)0x05000000)
#define OBJ_PAL ((volatile u16 *)0x05000200)
#define VRAM ((volatile u8 *)0x06000000)
#define OBJ_VRAM ((volatile u8 *)0x06010000)
#define OAM ((volatile u16 *)0x07000000)

#define SCREEN_W 240
#define SCREEN_H 160
#define CHARBLOCK_PLAY 0
#define CHARBLOCK_STATUS 1
#define MAP_PLAY 28
#define MAP_STATUS 30
#define MAP(n) ((volatile u16 *)(VRAM + (n) * 0x800))
#define FRAME_CYCLES 280896u

extern const u8 rom_prg[], rom_chr[], chr4[];

// 2C02 colours, as GBA BGR555.
#define RGB(r, g, b) (((r) >> 3) | ((g) >> 3) << 5 | ((b) >> 3) << 10)
static const u16 nes_colors[64] = {
  RGB(84,84,84), RGB(0,30,116), RGB(8,16,144), RGB(48,0,136), RGB(68,0,100), RGB(92,0,48), RGB(84,4,0), RGB(60,24,0),
  RGB(32,42,0), RGB(8,58,0), RGB(0,64,0), RGB(0,60,0), RGB(0,50,60), RGB(0,0,0), RGB(0,0,0), RGB(0,0,0),
  RGB(152,150,152), RGB(8,76,196), RGB(48,50,236), RGB(92,30,228), RGB(136,20,176), RGB(160,20,100), RGB(152,34,32), RGB(120,60,0),
  RGB(84,90,0), RGB(40,114,0), RGB(8,124,0), RGB(0,118,40), RGB(0,102,120), RGB(0,0,0), RGB(0,0,0), RGB(0,0,0),
  RGB(236,238,236), RGB(76,154,236), RGB(120,124,236), RGB(176,98,236), RGB(228,84,236), RGB(236,88,180), RGB(236,106,100), RGB(212,136,32),
  RGB(160,170,0), RGB(116,196,0), RGB(76,208,32), RGB(56,204,108), RGB(56,180,204), RGB(60,60,60), RGB(0,0,0), RGB(0,0,0),
  RGB(236,238,236), RGB(168,204,236), RGB(188,188,236), RGB(212,178,236), RGB(236,174,236), RGB(236,174,212), RGB(236,180,176), RGB(228,196,144),
  RGB(204,210,120), RGB(180,222,120), RGB(168,226,144), RGB(152,226,180), RGB(160,214,228), RGB(160,162,160), RGB(0,0,0), RGB(0,0,0),
};

static u8 loaded_play[4], loaded_status[4], loaded_obj[8];
static int cam_y;

static inline u32 now(void) { return TM0CNT_L | (u32)TM1CNT_L << 16; }

static void copy_chr(volatile u8 *dst, u8 page) {
  DMA3SAD = (u32)(chr4 + page * 0x800);
  DMA3DAD = (u32)dst;
  DMA3CNT = 0x84000000 | (0x800 / 4);
}

// Fill a tile map from the NES nametables: t is the NES scroll, and the map's first
// row holds picture line `line`. Returns the vertical offset into that row.
HOT __attribute__((long_call, noinline)) static int draw_bg(volatile u16 *map, u16 t, int line, int rows) {
  int sy = ((t >> 5) & 31) * 8 + ((t >> 12) & 7) + line;
  int nt_y = (t >> 11) & 1;
  while (sy >= 240) { sy -= 240; nt_y ^= 1; }
  int row = sy / 8;
  for (int r = 0; r < rows; r++) {
    int nty = nt_y;
    int ry = row + r;
    if (ry >= 30) { ry -= 30; nty ^= 1; }
    int col = (t & 31) + 1;  // the screen shows NES columns 8-247
    int ntx = (t >> 10) & 1;
    u16 *out = (u16 *)&map[r * 32];
    for (int c = 0; c < 31; c++, col++) {
      if (col >= 32) { col = 0; ntx ^= 1; }
      u16 base = 0x2000 + (nty << 11) + (ntx << 10);
      u8 tile = ciram[nt_index(base + ry * 32 + col)];
      u8 attr = ciram[nt_index(base + 0x3C0 + (ry >> 2) * 8 + (col >> 2))];
      u8 pal = attr >> (((ry & 2) << 1) | (col & 2)) & 3;
      out[c] = tile | pal << 12;
    }
  }
  return sy & 7;
}

HOT __attribute__((long_call, noinline)) static void draw_sprites(int top) {
  int tall = top_ctrl & 0x20;
  int n = 0;
  for (int i = 0; i < 64; i++) {
    const u8 *s = &oam[i * 4];
    int y = s[0] + 1 - top;
    int x = s[3] - 8;
    int h = tall ? 16 : 8;
    if (s[0] >= 0xEF || y <= -h || y >= SCREEN_H || x <= -8 || x >= SCREEN_W) continue;
    u32 tile = tall ? ((s[1] & 1) << 8) | (s[1] & 0xFE) : ((top_ctrl & 8) << 5) | s[1];
    u16 a0 = (y & 0xFF) | (tall ? 0x8000 : 0);
    u16 a1 = (x & 0x1FF) | ((s[2] & 0x40) ? 0x1000 : 0) | ((s[2] & 0x80) ? 0x2000 : 0);
    u16 a2 = tile | ((s[2] & 0x20) ? 2 : 1) << 10 | (s[2] & 3) << 12;
    OAM[n * 4] = a0;
    OAM[n * 4 + 1] = a1;
    OAM[n * 4 + 2] = a2;
    n++;
  }
  for (; n < 128; n++) OAM[n * 4] = 0x0200;  // hidden
}

// Keep Yumetaro on screen: the picture is taller than the GBA's.
static int camera(int play_h, int view_h) {
  int range = play_h - view_h;
  if (range <= 0) return 0;
  // $A4:$9A holds Yumetaro's feet as a screen number and a line on that screen.
  int want = range / 2;
  if (ram[0x90]) {
    int feet = (ram[0xA4] & 15) << 4 | ram[0x9A] >> 4;
    want = feet - view_h * 3 / 5;
  }
  if (want < 0) want = 0;
  if (want > range) want = range;
  int d = want - cam_y;
  if (d > 4) d = 4;
  if (d < -4) d = -4;
  cam_y += d;
  return cam_y;
}

static void wait_vblank(void) {
  while (VCOUNT >= SCREEN_H) {}
  while (VCOUNT < SCREEN_H) {}
}

static void present(void) {
  int bg_pages = (top_ctrl & 0x10) ? 4 : 0;
  for (int i = 0; i < 4; i++) {
    if (loaded_play[i] != top_chr[i + bg_pages]) {
      loaded_play[i] = top_chr[i + bg_pages];
      copy_chr(VRAM + CHARBLOCK_PLAY * 0x4000 + i * 0x800, loaded_play[i]);
    }
    if (split_line >= 0 && loaded_status[i] != split_chr[i + ((split_ctrl & 0x10) ? 4 : 0)]) {
      loaded_status[i] = split_chr[i + ((split_ctrl & 0x10) ? 4 : 0)];
      copy_chr(VRAM + CHARBLOCK_STATUS * 0x4000 + i * 0x800, loaded_status[i]);
    }
  }
  for (int i = 0; i < 8; i++) {
    if (loaded_obj[i] != top_chr[i]) {
      loaded_obj[i] = top_chr[i];
      copy_chr(OBJ_VRAM + i * 0x800, loaded_obj[i]);
    }
  }
  for (int i = 0; i < 16; i++) BG_PAL[i & 3 ? (i >> 2) * 16 + (i & 3) : (i >> 2) * 16] = nes_colors[palette[i & 3 ? i : 0] & 63];
  for (int i = 0; i < 16; i++) OBJ_PAL[(i >> 2) * 16 + (i & 3)] = nes_colors[palette[16 + i] & 63];

  int play_h = split_line > 0 && split_line < 240 ? split_line : 240;
  int status_h = 240 - play_h;
  if (status_h > 32) status_h = 32;  // below that the game only draws filler rows
  int view_h = SCREEN_H - status_h;
  int top = camera(play_h, view_h);

  // Rebuild a map only when what it shows has changed.
  static u16 map_t, map_split_t;
  static int map_top = -1, map_fine;
  if (nt_dirty || map_t != top_t || map_top != top) {
    map_fine = draw_bg(MAP(MAP_PLAY), top_t, top, 22);
    map_t = top_t;
    map_top = top;
  }
  BG0VOFS = map_fine;
  BG0HOFS = top_x;
  if (status_h) {
    static int status_fine;
    if (nt_dirty || map_split_t != split_t) {
      status_fine = draw_bg(MAP(MAP_STATUS), split_t, split_from_top ? play_h : 0, status_h / 8 + 1);
      map_split_t = split_t;
    }
    BG1HOFS = split_x;
    BG1VOFS = status_fine - view_h;
    // The status layer only exists in the bottom strip; the game has no sprites there.
    WIN0H = SCREEN_W;
    WIN0V = view_h << 8 | SCREEN_H;
    WININ = 0x0002;   // inside: BG1
    WINOUT = 0x0011;  // outside: BG0 and sprites
  }
  nt_dirty = 0;
  draw_sprites(top);
  DISPCNT = (ppu_mask & 0x18) ? 0x1040 | (status_h ? 0x2300 : 0x0100) : 0x0080;
}

#ifdef REPLAY
extern const u8 pad_stream[], pad_stream_end[];
extern const u32 expected[], expected_end[];
static const u8 *pad_at = pad_stream;
struct result {
  u32 magic, frames, cycles_sum, cycles_max, over_budget, checked, first_bad, done, untranslated;
};
volatile struct result result;
static u32 frame_start, window_sum, window_max, window_over;
static int nmi_index;

static void log_text(const char *a, u32 v) {
  volatile char *out = (volatile char *)0x04FFF600;
  REG16(0x04FFF780) = 0xC0DE;
  while (*a) *out++ = *a++;
  for (u32 d = 1000000000; d; d /= 10) *out++ = '0' + v / d % 10;
  *out = 0;
  REG16(0x04FFF700) = 0x100 | 3;  // level: info
}

static void report(void) {
  log_text("frames=", result.frames);
  log_text("cycles_sum=", result.cycles_sum);
  log_text("cycles_max=", result.cycles_max);
  log_text("over_budget=", result.over_budget);
  log_text("checked=", result.checked);
  log_text("first_bad=", result.first_bad);
  log_text("untranslated=", result.untranslated);
  log_text("done=", result.done);
}

u8 plat_pad_read(u16 a) { return pad_at < pad_stream_end ? *pad_at++ : 0x40; }

static u32 ram_hash(void) {
  u32 h = 2166136261u;
  for (int i = 0; i < 0x800; i++) {
    if (i == 0x100) i = 0x200;
    h = (h ^ ram[i]) * 16777619u;
  }
  return h | 1;
}

void plat_nmi(void) {
  u32 hash_start = now();
  u32 want = expected + nmi_index < expected_end ? expected[nmi_index] : 0;
  nmi_index++;
  if (want) {
    result.checked++;
    if (ram_hash() != want && !result.first_bad) result.first_bad = nmi_index;
  }
  if (nmi_index % 500 == 0) {
    log_text("nmi=", nmi_index);
    log_text("avg_500=", window_sum / 500);
    log_text("max_500=", window_max);
    log_text("over_500=", result.over_budget - window_over);
    log_text("first_bad=", result.first_bad);
    window_over = result.over_budget;
    window_sum = window_max = 0;
  }
  if (nmi_index >= (int)(expected_end - expected)) { result.done = 1; report(); }
  frame_start += now() - hash_start;  // the check is not part of the game's load
}
#else
static u8 pad_bits;
static int pad_pos;
void plat_nmi(void) {}
u8 plat_pad_read(u16 a) {
  if (a == 0x4017) return 0x40;
  // The game strobes, then takes 8 reads; start over after the 8th.
  if (pad_pos == 0) {
    u16 k = ~KEYINPUT;
    pad_bits = (k & 1) | (k >> 1 & 1) << 1 | (k >> 2 & 1) << 2 | (k >> 3 & 1) << 3
             | (k >> 6 & 1) << 4 | (k >> 7 & 1) << 5 | (k >> 5 & 1) << 6 | (k >> 4 & 1) << 7;
  }
  u8 v = pad_bits >> pad_pos & 1;
  pad_pos = (pad_pos + 1) & 7;
  return v | 0x40;
}
#endif

void plat_vblank(void) {
#ifdef REPLAY
  u32 t = now() - frame_start;
  if (result.frames) {
    result.cycles_sum += t;
    window_sum += t;
    if (t > window_max) window_max = t;
    if (t > result.cycles_max) result.cycles_max = t;
    if (t > FRAME_CYCLES) result.over_budget++;
  }
  result.frames++;
#endif
  wait_vblank();
#ifdef REPLAY
  frame_start = now();  // a frame's load is drawing plus the game
#endif
  present();
}

u32 trap(u32 pc) {
#ifdef REPLAY
  result.untranslated = pc;
  report();
#endif
  DISPCNT = 0;
  BG_PAL[0] = 0x001F;  // red: an instruction the 6502 does not have
  for (;;) {}
}

int main(void) {
  WAITCNT = 0x4317;  // 3/1 ROM waits with prefetch
  TM0CNT_L = 0; TM1CNT_L = 0;
  TM1CNT_H = 0x84;   // cascade
  TM0CNT_H = 0x80;
  DISPCNT = 0x0080;
  BG0CNT = CHARBLOCK_PLAY << 2 | MAP_PLAY << 8 | 1;
  BG1CNT = CHARBLOCK_STATUS << 2 | MAP_STATUS << 8;
  for (int i = 0; i < 4; i++) { loaded_play[i] = loaded_status[i] = 0xFF; }
  for (int i = 0; i < 8; i++) loaded_obj[i] = 0xFF;
  for (int n = 0; n < 128; n++) OAM[n * 4] = 0x0200;
  prg = rom_prg;
  chr = rom_chr;
#ifdef REPLAY
  result.magic = 0x47494D4B;
  frame_start = now();
#endif
  cpu_run();
  return 0;
}
