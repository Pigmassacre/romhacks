// Draws each frame on the GBA from the NES's nametables, OAM and palette.
#include "hw.h"

const u8 *chr4;

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

// The picture's layers: the top of the frame, then each region under it. Each has its
// own tiles and map.
#define LAYERS 3
static const u8 layer_map[LAYERS] = {28, 30, 26};
static u8 loaded_bg[LAYERS][4], loaded_obj[8], loaded_obj_lower[8];
static int cam_y;

static void copy_chr(volatile u8 *dst, u8 page) {
#ifdef HOST
  const u8 *from = chr4 + page * 0x800;
  for (int i = 0; i < 0x800; i++) dst[i] = from[i];
#else
  DMA3SAD = (u32)(chr4 + page * 0x800);
  DMA3DAD = (u32)dst;
  DMA3CNT = 0x84000000 | (0x800 / 4);
#endif
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
    if (col >= 32) { col = 0; ntx ^= 1; }
    const u8 *nt = &ciram[nt_index(0x2000 + (nty << 11) + (ntx << 10))];
    const u8 *tiles = nt + ry * 32;
    const u8 *attrs = nt + 0x3C0 + (ry >> 2) * 8;
    int attr_shift = (ry & 2) << 1;
    u16 *out = (u16 *)&map[r * 32];
    for (int c = 0; c < 31; c++, col++) {
      if (col >= 32) {
        col = 0;
        ntx ^= 1;
        nt = &ciram[nt_index(0x2000 + (nty << 11) + (ntx << 10))];
        tiles = nt + ry * 32;
        attrs = nt + 0x3C0 + (ry >> 2) * 8;
      }
      u32 pal = attrs[col >> 2] >> (attr_shift | (col & 2)) & 3;
      out[c] = tiles[col] | pal << 12;
    }
  }
  return sy & 7;
}

static int last_sprites;
// Sprites below a two-part picture's split see that part's graphics pages. Those are
// a second set of tiles, this far along in sprite memory.
#define OBJ_LOWER_TILES 512
HOT __attribute__((long_call, noinline)) static void draw_sprites(int top, int split) {
  int tall = top_ctrl & 0x20;
  int n = 0;
  for (int i = 0; i < 64; i++) {
    const u8 *s = &oam[i * 4];
    int y = s[0] + 1 - top;
    int x = s[3] - 8;
    int h = tall ? 16 : 8;
    if (s[0] >= 0xEF || y <= -h || y >= SCREEN_H || x <= -8 || x >= SCREEN_W) continue;
    u32 tile = tall ? ((s[1] & 1) << 8) | (s[1] & 0xFE) : ((top_ctrl & 8) << 5) | s[1];
    if (split >= 0) {
      int line = s[0] + 1;
      // One across the split would need both sets of tiles. Those behind the picture
      // are the game's own markers, hidden on the NES, so leave them out.
      if ((s[2] & 0x20) && line < split && line + h > split) continue;
      if (line >= split) tile += OBJ_LOWER_TILES;
    }
    u16 a0 = (y & 0xFF) | (tall ? 0x8000 : 0);
    u16 a1 = (x & 0x1FF) | ((s[2] & 0x40) ? 0x1000 : 0) | ((s[2] & 0x80) ? 0x2000 : 0);
    u16 a2 = tile | ((s[2] & 0x20) ? 2 : 1) << 10 | (s[2] & 3) << 12;
    OAM[n * 4] = a0;
    OAM[n * 4 + 1] = a1;
    OAM[n * 4 + 2] = a2;
    n++;
  }
  for (int i = n; i < last_sprites; i++) OAM[i * 4] = 0x0200;  // hidden
  last_sprites = n;
}

// The notices on the title screen, in a font of this port's own: 5x7, top row first,
// high bit on the left, white on black so they read on any ground. Their tiles sit
// after the second layer's, so they never clash.
#define TEXT_TILE 256
#define TEXT_PALETTE 15
static const struct { char c; u8 rows[7]; } font[] = {
  {' ', {0,0,0,0,0,0,0}},
  {'-', {0,0,0,31,0,0,0}},
  {'A', {14,17,17,31,17,17,17}},
  {'B', {30,17,17,30,17,17,30}},
  {'C', {14,17,16,16,16,17,14}},
  {'D', {30,17,17,17,17,17,30}},
  {'E', {31,16,16,30,16,16,31}},
  {'G', {14,17,16,23,17,17,15}},
  {'I', {14,4,4,4,4,4,14}},
  {'L', {16,16,16,16,16,16,31}},
  {'M', {17,27,21,21,17,17,17}},
  {'N', {17,25,21,19,17,17,17}},
  {'O', {14,17,17,17,17,17,14}},
  {'P', {30,17,17,30,16,16,16}},
  {'R', {30,17,17,30,20,18,17}},
  {'S', {15,16,16,14,1,1,30}},
  {'T', {31,4,4,4,4,4,4}},
  {'Y', {17,17,10,4,4,4,4}},
};
#define FONT_SIZE (sizeof font / sizeof font[0])
#define NOTICE_ROW 18
static const char *const notices[2] = {"PORT BY PIGMASSACRE", "AI SLOP - DO NOT PLAY"};

static void font_init(void) {
  volatile u16 *tiles = (volatile u16 *)(VRAM + CHARBLOCK_TEXT * 0x4000 + TEXT_TILE * 32);
  for (u32 g = 0; g < FONT_SIZE; g++) {
    u8 px[8][8];
    for (int y = 0; y < 8; y++)
      for (int x = 0; x < 8; x++)
        px[y][x] = y < 7 && x >= 1 && x < 6 && (font[g].rows[y] >> (5 - x) & 1) ? 1 : 2;
    for (int y = 0; y < 8; y++) {
      tiles[g * 16 + y * 2] = px[y][0] | px[y][1] << 4 | px[y][2] << 8 | px[y][3] << 12;
      tiles[g * 16 + y * 2 + 1] = px[y][4] | px[y][5] << 4 | px[y][6] << 8 | px[y][7] << 12;
    }
  }
  BG_PAL[TEXT_PALETTE * 16 + 1] = RGB(255, 255, 255);
  BG_PAL[TEXT_PALETTE * 16 + 2] = RGB(0, 0, 0);
}

static void draw_notices(void) {
  volatile u16 *map = MAP(MAP_TEXT);
  for (int i = 0; i < 32 * 32; i++) map[i] = TEXT_TILE + FONT_SIZE;  // never drawn: clear
  for (int n = 0; n < 2; n++) {
    const char *t = notices[n];
    int len = 0;
    while (t[len]) len++;
    int left = (30 - len) / 2;
    // A margin on each side of the black bar. The blank is the font's first letter.
    map[(NOTICE_ROW + n) * 32 + left - 1] = TEXT_TILE | TEXT_PALETTE << 12;
    map[(NOTICE_ROW + n) * 32 + left + len] = TEXT_TILE | TEXT_PALETTE << 12;
    for (int i = 0; i < len; i++) {
      u32 g = 0;
      while (g < FONT_SIZE && font[g].c != t[i]) g++;
      map[(NOTICE_ROW + n) * 32 + left + i] = (TEXT_TILE + g) | TEXT_PALETTE << 12;
    }
  }
}

// The title loads its logo into these background pages, and nothing else does.
static inline int on_title(void) {
  return top_chr[5] == 0x65 && top_chr[6] == 0x66 && top_chr[7] == 0x67;
}
#define TITLE_TOP 28   // shows the whole logo, START and CONTINUE
#define STATUS_FROM 184  // a mid-frame change this low is the status bar

// Which lines of a screen without a status bar have something on them: everything
// that differs from the screen's top-left tile, and the sprites.
static int content_centre(void) {
  const u8 *nt = &ciram[nt_index(0x2000 + ((top_t >> 10) & 3) * 0x400)];
  u8 blank = nt[0];
  int first = 30, last = -1;
  for (int r = 0; r < 30; r++) {
    const u8 *row = nt + r * 32;
    for (int c = 1; c < 31; c++) {
      if (row[c] != blank) {
        if (r < first) first = r;
        last = r;
        break;
      }
    }
  }
  if (last < 0) return 120;
  return (first + last + 1) * 4;
}

// Keep what matters on screen: the picture is taller than the GBA's.
static int camera(int play_h, int view_h, int has_status) {
  int range = play_h - view_h;
  if (range <= 0) return 0;
  int want;
  if (on_title()) {
    cam_y = TITLE_TOP;
    return cam_y;
  }
  if (has_status && ram[0x90]) {
    // $A4:$9A holds Yumetaro's feet as a screen number and a line on that screen.
    int feet = (ram[0xA4] & 15) << 4 | ram[0x9A] >> 4;
    want = feet - view_h * 3 / 5;
  } else {
    static int centre = 120;
    if (nt_dirty) centre = content_centre();
    cam_y = centre - view_h / 2;
    if (cam_y < 0) cam_y = 0;
    if (cam_y > range) cam_y = range;
    return cam_y;
  }
  if (want < 0) want = 0;
  if (want > range) want = range;
  int d = want - cam_y;
  if (d > 4) d = 4;
  if (d < -4) d = -4;
  cam_y += d;
  return cam_y;
}

void video_init(void) {
  DISPCNT = 0x0080;
  for (int i = 0; i < LAYERS; i++) {
    REG16(0x04000008 + i * 2) = i << 2 | layer_map[i] << 8 | 1;
    for (int p = 0; p < 4; p++) loaded_bg[i][p] = 0xFF;
  }
  BG3CNT = CHARBLOCK_TEXT << 2 | MAP_TEXT << 8;
  for (int i = 0; i < 8; i++) loaded_obj[i] = loaded_obj_lower[i] = 0xFF;
  for (int n = 0; n < 128; n++) OAM[n * 4] = 0x0200;
  font_init();
  draw_notices();
}

static void load_bg_pages(int layer, const u8 *chr_set, u8 ctrl) {
  int from = (ctrl & 0x10) ? 4 : 0;
  for (int i = 0; i < 4; i++) {
    if (loaded_bg[layer][i] != chr_set[i + from]) {
      loaded_bg[layer][i] = chr_set[i + from];
      copy_chr(VRAM + layer * 0x4000 + i * 0x800, chr_set[i + from]);
    }
  }
}

// What a layer's map holds now, so it is only rebuilt when that changes.
static struct { int t, row; } map_key[LAYERS] = {{-1, -1}, {-1, -1}, {-1, -1}};

static int layer_map_up_to_date(int layer, int t, int row) {
  if (!nt_dirty && map_key[layer].t == t && map_key[layer].row == row) return 1;
  map_key[layer].t = t;
  map_key[layer].row = row;
  return 0;
}

void video_present(void) {
  load_bg_pages(0, top_chr, top_ctrl);
  for (int i = 0; i < 8; i++) {
    if (loaded_obj[i] != top_chr[i]) {
      loaded_obj[i] = top_chr[i];
      copy_chr(OBJ_VRAM + i * 0x800, loaded_obj[i]);
    }
  }
  if (palette_dirty) {
    palette_dirty = 0;
    for (int i = 0; i < 16; i++) BG_PAL[(i >> 2) * 16 + (i & 3)] = nes_colors[palette[i & 3 ? i : 0] & 63];
    for (int i = 0; i < 16; i++) OBJ_PAL[(i >> 2) * 16 + (i & 3)] = nes_colors[palette[16 + i] & 63];
  }

  // A region low on the screen is the status bar, which stays on screen whatever the
  // camera does, and nothing after it matters. One higher up is part of one picture,
  // like the title's logo over its scrolling ground, and keeps its place in it. The
  // game times these for a row boundary, and the count here can be a line short.
  int parts = 0, status = -1, part_line[LAYERS - 1], status_line = 240;
  for (int i = 0; i < region_count && parts + (status >= 0) < LAYERS - 1 && status < 0; i++) {
    int line = (regions[i].line + 7) & ~7;
    if (line >= STATUS_FROM && line < 240) {
      status = i;
      status_line = line;
    } else if (line > 0 && line < STATUS_FROM) {
      part_line[parts++] = i;
    }
  }
  int status_h = status >= 0 ? 240 - status_line : 0;
  if (status_h > 32) status_h = 32;  // below that the game only draws filler rows
  int view_h = SCREEN_H - status_h;
  int title = on_title();
  int top = camera(status_line, view_h, status >= 0);

  int picture_y = ((top_t >> 5) & 31) * 8 + ((top_t >> 12) & 7) + top;
  if (!layer_map_up_to_date(0, top_t & 0x0C1F, picture_y >> 3)) draw_bg(MAP(layer_map[0]), top_t, top, 22);
  BG0VOFS = picture_y & 7;
  BG0HOFS = top_x;

  // Windows: inside window 0 is the bottom layer, inside window 1 the next one up,
  // and outside them both the top of the frame.
  u16 enable = 0x0100 | (title ? 0x0800 : 0);
  u16 window_on = 0;
  u16 win_in = 0;
  int layer = 1;
  for (int p = 0; p < parts; p++, layer++) {
    struct region *r = &regions[part_line[p]];
    int t = (r->t & 0x041F) | (r->own_row ? r->t & ~0x041F : top_t & ~0x041F);
    int y = ((t >> 5) & 31) * 8 + ((t >> 12) & 7) + (r->own_row ? top - ((r->line + 7) & ~7) + ((r->line + 7) & ~7) : top);
    load_bg_pages(layer, r->chr, r->ctrl);
    if (!layer_map_up_to_date(layer, t, y >> 3)) draw_bg(MAP(layer_map[layer]), t, top, 22);
    REG16(0x04000010 + layer * 4) = r->x;
    REG16(0x04000012 + layer * 4) = y & 7;
    int from = ((r->line + 7) & ~7) - top;
    if (from < 0) from = 0;
    if (from > view_h) from = view_h;
    u16 v = from << 8 | (status >= 0 ? view_h : SCREEN_H);
    u16 inside = 1 << layer | 0x18;  // with the sprites and the notices
    if (p == parts - 1 && status < 0) {
      WIN0V = v; win_in |= inside; window_on |= 0x2000;
    } else {
      WIN1V = v; win_in |= inside << 8; window_on |= 0x4000;
    }
    enable |= 0x100 << layer;
  }
  if (status >= 0) {
    struct region *r = &regions[status];
    load_bg_pages(layer, r->chr, r->ctrl);
    int key = r->t | r->own_row << 16;
    int fine = ((r->own_row ? 0 : status_line) + ((r->t >> 5) & 31) * 8 + ((r->t >> 12) & 7)) & 7;
    if (!layer_map_up_to_date(layer, key, status_line))
      draw_bg(MAP(layer_map[layer]), r->t, r->own_row ? 0 : status_line, status_h / 8 + 1);
    REG16(0x04000010 + layer * 4) = r->x;
    REG16(0x04000012 + layer * 4) = fine - view_h;
    WIN0V = view_h << 8 | SCREEN_H;
    win_in |= 1 << layer;  // no sprites on the status bar
    window_on |= 0x2000;
    enable |= 0x100 << layer;
  }
  WIN0H = SCREEN_W;
  WIN1H = SCREEN_W;
  WININ = win_in;
  WINOUT = 0x0019;  // the top of the frame, sprites and the notices
  nt_dirty = 0;
  int lower_from = -1;
  if (parts) {
    struct region *r = &regions[part_line[0]];
    lower_from = (r->line + 7) & ~7;
    for (int i = 0; i < 8; i++) {
      if (loaded_obj_lower[i] != r->chr[i]) {
        loaded_obj_lower[i] = r->chr[i];
        copy_chr(OBJ_VRAM + OBJ_LOWER_TILES * 32 + i * 0x800, loaded_obj_lower[i]);
      }
    }
  }
  draw_sprites(top, lower_from);
  if (ppu_mask & 0x18) {
    DISPCNT = 0x1040 | enable | window_on;
  } else {
    // The GBA's own blanking is white, and the NES's is black.
    DISPCNT = 0;
    BG_PAL[0] = 0;
    palette_dirty = 1;
  }
}
