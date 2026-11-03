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
static u16 loaded_bg[LAYERS][4];
static u8 loaded_obj[8], loaded_obj_lower[8];
static int cam_y;

static void copy_chr(volatile u8 *dst, u32 page) {
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
// Sprites at or below status_line belong to the status bar, like the health pips, and
// are drawn on it wherever the camera is. With masks, each sprite behind the picture
// also marks the sprite window, for the title's clouds.
//
// The game fills OAM from slot 8 up on even frames and from slot 63 down on odd ones,
// to share out the flicker of the NES's 8 sprites on a line. The GBA has no such limit,
// and overlapping sprites would swap places 30 times a second, so odd frames are read
// backwards.
//
// The portal hides Yumetaro both ways at once on the NES: on even frames its black box
// is in front of him, on odd ones 8 blank sprites come first on the lines below it, and
// the NES's limit of 8 on a line leaves him out. The second needs doing by hand: on the
// lines with 8 blanks, band_from to band_to on screen, no sprite shows.
static int band_from, band_to;
#define BLANK(s) ((s)[1] == 0x80 && ((s)[2] & 0x20) && (s)[0] < 0xEF)

// The title's third entry, OPTIONS, under START and CONTINUE: the game's own letters,
// tall sprites with the letter in their lower half, and a P drawn to match in a tile
// the title's sprites never use. All three go up 8 lines, to sit between the logo and
// the bottom of the GBA's screen.
// gba.c moves title_cursor; on OPTIONS, START and CONTINUE are both grey, as the
// game draws the one not chosen, and OPTIONS blinks as the game blinks its choice.
int title_cursor;
#define ENTRY(s) (!((s)[2] & 0x20) && ((s)[0] == 124 || (s)[0] == 140))
#define ENTRY_RISE 8
#define OPTIONS_Y (156 - ENTRY_RISE)
#define P_TILE 511
static const u8 options_tiles[7] = {0x28, 0, 0x32, 0x38, 0x28, 0x36, 0x30};  // O P T I O N S
static int p_loaded;
__attribute__((noinline)) static void put_p_tile(int tile);
// OPTIONS and the title's own sprites. Not in fast RAM: only the title has them.
static int blink;

// The game's sprites, with START and CONTINUE moved up, and grey while OPTIONS is chosen.
__attribute__((noinline)) static const u8 *title_sprites(void) {
  static u8 copy[256] SLOW_RAM;
  blink = 1;
  for (int i = 0; i < 256; i += 4) {
    u8 *s = &copy[i];
    s[0] = oam[i]; s[1] = oam[i + 1]; s[2] = oam[i + 2]; s[3] = oam[i + 3];
    if (!ENTRY(s)) continue;
    if (s[0] == ((ram[5] & 1) ? 140 : 124)) blink = s[2] & 3;
    if (title_cursor == 2) s[2] = (s[2] & ~3) | 1;
    s[0] -= ENTRY_RISE;
  }
  return copy;
}

__attribute__((noinline)) static int draw_options(int n, int top, int split) {
  int lower = split >= 0 && OPTIONS_Y + 1 >= split ? OBJ_LOWER_TILES : 0;
  put_p_tile(P_TILE + lower);
  int y = OPTIONS_Y + 1 - top;
  u16 pal = (title_cursor == 2 ? blink : 1) << 12 | 1 << 10;
  for (int i = 0; i < 7; i++, n++) {
    if (options_tiles[i]) {
      OAM[n * 4] = (y & 0xFF) | 0x8000;
      OAM[n * 4 + 2] = (options_tiles[i] + lower) | pal;
    } else {
      OAM[n * 4] = (y + 8) & 0xFF;
      OAM[n * 4 + 2] = (P_TILE + lower) | pal;
    }
    OAM[n * 4 + 1] = 88 + i * 8;
  }
  return n;
}

HOT __attribute__((long_call, noinline)) static void draw_sprites(int top, int split, int status_line, int view_h, int masks) {
  int tall = top_ctrl & 0x20;
  int n = 0;
  int blanks = 0;
  for (int i = 8; i < 64; i++) blanks += BLANK(&oam[i * 4]);
  band_from = band_to = 0;
  if (blanks >= 8) {
    u8 count[256] = {0};
    int lo = 256, hi = 0;
    for (int i = 8; i < 64; i++) {
      const u8 *s = &oam[i * 4];
      if (!BLANK(s)) continue;
      for (int l = s[0] + 1; l < s[0] + 1 + (tall ? 16 : 8) && l < 256; l++) {
        if (++count[l] == 8) {
          if (l < lo) lo = l;
          if (l > hi) hi = l;
        }
      }
    }
    if (lo <= hi) {
      band_from = lo - top < 0 ? 0 : lo - top;
      band_to = hi + 1 - top > view_h ? view_h : hi + 1 - top;
    }
  }
  // Which way this frame went shows in which end is in use. Only with both in use does
  // it take the game's frame counter, whose parity picks the way.
  int odd = (oam[8 * 4] < 0xEF) == (oam[63 * 4] < 0xEF) ? ram[0xED] & 1 : oam[63 * 4] < 0xEF;
  const u8 *sprites = masks ? title_sprites() : oam;
  for (int k = 0; k < 64; k++) {
    int i = k < 8 || !odd ? k : 71 - k;
    const u8 *s = &sprites[i * 4];
    int on_status = s[0] + 1 >= status_line;
    int y = on_status ? s[0] + 1 - status_line + view_h : s[0] + 1 - top;
    int x = s[3] - 8;
    int h = tall ? 16 : 8;
    if (s[0] >= 0xEF || y <= -h || y >= (on_status ? SCREEN_H : view_h) || x <= -8 || x >= SCREEN_W) continue;
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
    u16 a2 = tile | ((s[2] & 0x20) ? 2 : on_status ? 0 : 1) << 10 | (s[2] & 3) << 12;
    if (masks && (s[2] & 0x20)) {
      OAM[n * 4] = a0 | 0x0800;
      OAM[n * 4 + 1] = a1;
      OAM[n * 4 + 2] = a2;
      n++;
    }
    OAM[n * 4] = a0;
    OAM[n * 4 + 1] = a1;
    OAM[n * 4 + 2] = a2;
    n++;
  }
  if (masks && n + 7 <= 128) n = draw_options(n, top, split);
  for (int i = n; i < last_sprites; i++) OAM[i * 4] = 0x0200;  // hidden
  last_sprites = n;
}

// The title's own words, on the fourth layer: the notices, in the style of START and
// CONTINUE, and ADVANCE in the logo's bar in place of its katakana. The font is the
// menu's, a bold 7x7: the letters it has are copied, the others drawn to match. The
// options menu is on it too, over the logo.
// Each letter has three tiles: grey with a black shadow down and right, for the sky,
// black on the bar's white, and black on the menu's white. Their tiles sit after the
// second layer's, so they never clash.
#define TEXT_TILE 256
#define NOTICE_PALETTE 15
#define BAR_PALETTE 14
#define SPLASH_PALETTE 13
static const struct { char c; char rows[7][8]; } font[] = {
  {' ', {".......", ".......", ".......", ".......", ".......", ".......", "......."}},
  {'-', {".......", ".......", ".......", ".#####.", ".......", ".......", "......."}},
  {'!', {"..##...", "..##...", "..##...", "..##...", "..##...", ".......", "..##..."}},
  {'.', {".......", ".......", ".......", ".......", ".......", "..##...", "..##..."}},
  {'>', {".##....", "..##...", "...##..", "....##.", "...##..", "..##...", ".##...."}},
  {'1', {"..##...", ".###...", "..##...", "..##...", "..##...", "..##...", ".####.."}},
  {'5', {"######.", "##.....", "######.", ".....##", ".....##", "##...##", ".#####."}},
  {'A', {"..###..", ".##.##.", "##...##", "##...##", "#######", "##...##", "##...##"}},
  {'B', {"######.", "##...##", "##...##", "######.", "##...##", "##...##", "######."}},
  {'C', {"..####.", ".##..##", "##.....", "##.....", "##.....", ".##..##", "..####."}},
  {'D', {"#####..", "##..##.", "##...##", "##...##", "##...##", "##..##.", "#####.."}},
  {'E', {"#######", "##.....", "##.....", "######.", "##.....", "##.....", "#######"}},
  {'F', {"#######", "##.....", "##.....", "######.", "##.....", "##.....", "##....."}},
  {'G', {"..####.", ".##....", "##.....", "##..###", "##...##", ".##..##", "..#####"}},
  {'I', {".######", "...##..", "...##..", "...##..", "...##..", "...##..", ".######"}},
  {'J', {"....###", ".....##", ".....##", ".....##", "##...##", "##...##", ".#####."}},
  {'K', {"##...##", "##..##.", "##.##..", "####...", "##.##..", "##..##.", "##...##"}},
  {'L', {"##.....", "##.....", "##.....", "##.....", "##.....", "##.....", "#######"}},
  {'M', {"##...##", "###.###", "#######", "##.#.##", "##...##", "##...##", "##...##"}},
  {'N', {"##...##", "###..##", "####.##", "#######", "##.####", "##..###", "##...##"}},
  {'O', {".#####.", "##...##", "##...##", "##...##", "##...##", "##...##", ".#####."}},
  {'P', {"######.", "##...##", "##...##", "######.", "##.....", "##.....", "##....."}},
  {'R', {"######.", "##...##", "##...##", "##..###", "#####..", "##.###.", "##..###"}},
  {'S', {".####..", "##..##.", "##.....", ".#####.", ".....##", "##...##", ".#####."}},
  {'T', {".######", "...##..", "...##..", "...##..", "...##..", "...##..", "...##.."}},
  {'U', {"##...##", "##...##", "##...##", "##...##", "##...##", "##...##", ".#####."}},
  {'V', {"##...##", "##...##", "##...##", ".##.##.", ".##.##.", "..###..", "...#..."}},
  {'Y', {"##...##", "##...##", ".##.##.", "..###..", "...##..", "...##..", "...##.."}},
};
#define FONT_SIZE (sizeof font / sizeof font[0])
#define BAR_TILE (TEXT_TILE + FONT_SIZE)      // then the bar's: its letters, then its ends
#define MENU_TILE (BAR_TILE + FONT_SIZE + 2)
#define CLEAR_TILE (MENU_TILE + FONT_SIZE)
// The title's camera: the line of the NES's picture at the top of the screen. It leaves
// the sky above the logo room for the notice.
#define TITLE_TOP 15
// Rows of the map, which scrolls so that the bar's white inside, lines 99 to 105 of the
// NES's picture, starts a row. The notice goes on the sky above the logo, as Gimmick!
// 1.5's do.
#define TEXT_SCROLL (TITLE_TOP - 1)
#define BAR_ROW 13
#define BAR_LEFT 4      // its tiles: the bar's ends are lines at x 32 and 207
#define BAR_RIGHT 25
#define NOTICE_ROW 2
#define CREDIT "PORT BY PIGMASSACRE"
#define WARNING "AI SLOP - DO NOT PLAY"
static const char bar_text[] = "A  D  V  A  N  C  E";

static int is_ink(int g, int x, int y) {
  return x >= 0 && x < 7 && y >= 0 && y < 7 && font[g].rows[y][x] == '#';
}

static void put_tile(int tile, u8 px[8][8]) {
  volatile u16 *t = (volatile u16 *)(VRAM + CHARBLOCK_TEXT * 0x4000 + tile * 32);
  for (int y = 0; y < 8; y++) {
    t[y * 2] = px[y][0] | px[y][1] << 4 | px[y][2] << 8 | px[y][3] << 12;
    t[y * 2 + 1] = px[y][4] | px[y][5] << 4 | px[y][6] << 8 | px[y][7] << 12;
  }
}

static void font_init(void) {
  u8 px[8][8];
  for (u32 g = 0; g < FONT_SIZE; g++) {
    for (int y = 0; y < 8; y++)
      for (int x = 0; x < 8; x++)
        px[y][x] = is_ink(g, x, y) ? 1 : is_ink(g, x - 1, y - 1) ? 2 : 0;
    put_tile(TEXT_TILE + g, px);
    // On the bar, its bottom line shows through.
    for (int y = 0; y < 8; y++)
      for (int x = 0; x < 8; x++)
        px[y][x] = y == 7 ? 0 : is_ink(g, x, y) ? 1 : 3;
    put_tile(BAR_TILE + g, px);
    px[7][0] = px[7][1] = px[7][2] = px[7][3] = px[7][4] = px[7][5] = px[7][6] = px[7][7] = 3;
    put_tile(MENU_TILE + g, px);
  }
  for (int end = 0; end < 2; end++) {
    for (int y = 0; y < 8; y++)
      for (int x = 0; x < 8; x++)
        px[y][x] = y == 7 || x == (end ? 7 : 0) ? 0 : 3;
    put_tile(BAR_TILE + FONT_SIZE + end, px);
  }
  for (int y = 0; y < 8; y++)
    for (int x = 0; x < 8; x++) px[y][x] = 0;
  put_tile(CLEAR_TILE, px);
  BG_PAL[NOTICE_PALETTE * 16 + 1] = nes_colors[0x10];
  BG_PAL[NOTICE_PALETTE * 16 + 2] = RGB(0, 0, 0);
  BG_PAL[SPLASH_PALETTE * 16 + 1] = nes_colors[0x30];
  BG_PAL[BAR_PALETTE * 16 + 1] = RGB(0, 0, 0);
  BG_PAL[BAR_PALETTE * 16 + 3] = nes_colors[0x30];
}

static int glyph(char c) {
  u32 g = 0;
  while (g < FONT_SIZE && font[g].c != c) g++;
  return g < FONT_SIZE ? g : 0;
}

// OPTIONS' P, as the game draws its letters: colour 3, with colour 1 down and right.
__attribute__((noinline)) static void put_p_tile(int tile) {
  int g = glyph('P');
  volatile u16 *t = (volatile u16 *)(OBJ_VRAM + tile * 32);
  for (int y = 0; y < 8; y++) {
    u32 row = 0;
    for (int x = 0; x < 8; x++)
      row |= (u32)(is_ink(g, x, y) ? 3 : is_ink(g, x - 1, y - 1) ? 1 : 0) << (x * 4);
    t[y * 2] = row;
    t[y * 2 + 1] = row >> 16;
  }
  p_loaded = 1;
}

// A line of text, across the middle of the screen.
static void text_line(volatile u16 *map, int row, const char *t, int palette) {
  int len = 0;
  while (t[len]) len++;
  int left = (30 - len) / 2;
  for (int i = 0; i < len; i++) map[row * 32 + left + i] = (TEXT_TILE + glyph(t[i])) | palette << 12;
}

static void draw_notices(void) {
  volatile u16 *map = MAP(MAP_TEXT);
  for (int i = 0; i < 32 * 32; i++) map[i] = CLEAR_TILE;
  text_line(map, NOTICE_ROW, WARNING, NOTICE_PALETTE);
  int len = sizeof bar_text - 1, left = BAR_LEFT + (BAR_RIGHT - BAR_LEFT + 1 - len) / 2;
  for (int c = BAR_LEFT; c <= BAR_RIGHT; c++) {
    int tile = c == BAR_LEFT ? BAR_TILE + FONT_SIZE : c == BAR_RIGHT ? BAR_TILE + FONT_SIZE + 1
             : BAR_TILE + (c >= left && c < left + len ? glyph(bar_text[c - left]) : 0);
    map[BAR_ROW * 32 + c] = tile | BAR_PALETTE << 12;
  }
  REG16(0x0400001C) = 0;
  REG16(0x0400001E) = TEXT_SCROLL;
}

// The first screen, before the game's own: who made the port, in white, and the
// warning, in the title's grey, on black like SUNSOFT PRESENTS. gba.c shows it.
void splash_draw(int show) {
  volatile u16 *map = MAP(MAP_TEXT);
  if (!show) {
    DISPCNT = 0x0080;
    draw_notices();
    return;
  }
  for (int i = 0; i < 32 * 32; i++) map[i] = CLEAR_TILE;
  text_line(map, 9, CREDIT, SPLASH_PALETTE);
  text_line(map, 11, WARNING, NOTICE_PALETTE);
  REG16(0x0400001C) = 0;
  REG16(0x0400001E) = 4;  // the two lines, 72 to 95 of the map, about the screen's middle
  BG_PAL[0] = 0;
  DISPCNT = 0x0800;
}

// Gimmick! 1.5's features as options: a white box over the logo, from the title's
// OPTIONS. The rows it covers go back to clear when it closes.
#define MENU_TOP 4
#define MENU_ROWS 9
static const char *const option_names[5] = {"STAR RECALL", "SKIPPING STONES", "TAP TO SUMMON",
                                             "COYOTE TIME", "JUMP BUFFERING"};

static void menu_text(int row, int col, const char *t) {
  volatile u16 *map = MAP(MAP_TEXT);
  for (; *t; t++, col++) map[row * 32 + col] = (MENU_TILE + glyph(*t)) | BAR_PALETTE << 12;
}

void menu_draw(int open, int cursor, int opts) {
  volatile u16 *map = MAP(MAP_TEXT);
  for (int r = MENU_TOP; r < MENU_TOP + MENU_ROWS; r++)
    for (int c = BAR_LEFT; c <= BAR_RIGHT; c++)
      map[r * 32 + c] = open ? MENU_TILE | BAR_PALETTE << 12 : CLEAR_TILE;
  if (!open) return;
  menu_text(MENU_TOP + 1, BAR_LEFT + 2, "GIMMICK! 1.5 OPTIONS");
  for (int i = 0; i < 5; i++) {
    int row = MENU_TOP + 3 + i;
    if (i == cursor) menu_text(row, BAR_LEFT + 1, ">");
    menu_text(row, BAR_LEFT + 2, option_names[i]);
    menu_text(row, BAR_RIGHT - 3, opts >> i & 1 ? " ON" : "OFF");
  }
}

// The title loads its logo into these background pages, and nothing else does.
static inline int on_title(void) {
  return top_chr[5] == 0x65 && top_chr[6] == 0x66 && top_chr[7] == 0x67;
}
int video_on_title(void) { return on_title(); }
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
    // $A4:$9A holds Yumetaro's feet: the room in the top 4 bits, then the line in it.
    int feet = (ram[0xA4] & 15) << 4 | ram[0x9A] >> 4;
    want = feet - view_h * 3 / 5;
  } else {
    // The game can fill a nametable while the scroll still points at another, and only
    // then point at it, so a change of either means looking again.
    static int centre = 120, centre_nt = -1;
    int nt = (top_t >> 10) & 3;
    if (nt_dirty || nt != centre_nt) {
      centre = content_centre();
      centre_nt = nt;
    }
    cam_y = centre - view_h / 2;
    if (cam_y < 0) cam_y = 0;
    if (cam_y > range) cam_y = range;
    return cam_y;
  }
  if (want < 0) want = 0;
  if (want > range) want = range;
  // Going to another room, the NES shows it at once, and so does the camera. Easing
  // over to Yumetaro's new place looked like the camera racing to catch up.
  static int last_room = -1;
  if (ram[0xA4] >> 4 != last_room) {
    last_room = ram[0xA4] >> 4;
    cam_y = want;
    return cam_y;
  }
  int d = want - cam_y;
  if (d > 4) d = 4;
  if (d < -4) d = -4;
  cam_y += d;
  return cam_y;
}

// Parallax clouds, from tools/parallax.py's data: which version of each page the stage
// has, then per stage the clouds' map, palette and top line, then their tiles and maps.
// The clouds' tiles go after the stage's own, and their map in a block of its own.
#define CLOUD_PAGE 0x01
#define CLOUD_TILE 256
#define CLOUD_MAP 29
#define PAR_ALIAS(p) parallax[p]
#define PAR_MASK_BASE parallax[128]
#define PAR_STAGE(s) (parallax + 132 + (s) * 4)
#define PAR_TILES (parallax + 256)
#define PAR_MAPS (parallax + 256 + 67 * 32)
const u8 *parallax;

// The stages with clouds behind them, in play, with the clouds' page in.
static int parallax_stage(int parts, int status) {
  if (parts || status < 0 || on_title() || ram[0x4A] != 1 || !ram[0x90] || ram[0x1B] >= 8) return -1;
  if (top_chr[5] != CLOUD_PAGE && top_chr[6] != CLOUD_PAGE) return -1;
  return PAR_STAGE(ram[0x1B])[0] ? ram[0x1B] : -1;
}

static void draw_clouds(int stage) {
  static int drawn = -1;
  if (stage == drawn) return;
  drawn = stage;
  const u8 *st = PAR_STAGE(stage), *cells = PAR_MAPS + (st[0] - 1) * 1024;
  volatile u16 *map = MAP(CLOUD_MAP);
  for (int i = 0; i < 32 * 32; i++) map[i] = (CLOUD_TILE + cells[i]) | st[1] << 12;
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
  volatile u16 *to = (volatile u16 *)(VRAM + CLOUD_TILE * 32);
  for (int i = 0; i < 67 * 16; i++) to[i] = PAR_TILES[i * 2] | PAR_TILES[i * 2 + 1] << 8;
}

// how: 0 the pages as they are, 1 the stage's version for parallax, 2 their masks.
static void load_bg_pages(int layer, const u8 *chr_set, u8 ctrl, int how) {
  int from = (ctrl & 0x10) ? 4 : 0;
  for (int i = 0; i < 4; i++) {
    u32 page = chr_set[i + from];
    if (how == 1 && PAR_ALIAS(page) != 0xFF) page = PAR_ALIAS(page);
    if (how == 2) page += PAR_MASK_BASE;
    if (loaded_bg[layer][i] != page) {
      loaded_bg[layer][i] = page;
      copy_chr(VRAM + layer * 0x4000 + i * 0x800, page);
    }
  }
}

// The world map arrives as the SNES port's does in Mode 7: the island spins in from far
// away and settles on the picture the NES shows, and from there the usual drawing takes
// over. The GBA's affine layer has one byte a cell and 8-bit tiles, so each tile and
// palette the island uses becomes a tile, made from the nametable when the map opens.
#define MAP_FRAMES 72
#define AFFINE_MAP 24
static const u16 quarter_sin[65] = {0, 6, 13, 19, 25, 31, 38, 44, 50, 56, 62, 68, 74, 80, 86, 92, 98, 104, 109,
  115, 121, 126, 132, 137, 142, 147, 152, 157, 162, 167, 172, 177, 181, 185, 190, 194, 198, 202, 206, 209,
  213, 216, 220, 223, 226, 229, 231, 234, 237, 239, 241, 243, 245, 247, 248, 250, 251, 252, 253, 254, 255,
  255, 256, 256, 256};

static int sin256(int a) {  // a in 1/256 turns, result 8.8
  a &= 255;
  return a <= 64 ? quarter_sin[a] : a <= 128 ? quarter_sin[128 - a] : a <= 192 ? -quarter_sin[a - 128] : -quarter_sin[256 - a];
}

static inline int on_world_map(void) {
  return (top_ctrl & 0x10) && top_chr[4] == 0x54 && top_chr[5] == 0x55;
}

// The island's cells, as tiles of their own: 0 when that does not fit.
static int build_island(int top) {
  static u16 pairs[256] SLOW_RAM;
  static u8 ids[1024] SLOW_RAM;  // by tile and palette
  int count = 0;
  for (int i = 0; i < 1024; i++) ids[i] = 0xFF;
  const u8 *pages = top_chr + 4;
  volatile u8 *map = VRAM + AFFINE_MAP * 0x800;
  int sy = ((top_t >> 5) & 31) * 8 + ((top_t >> 12) & 7);
  int nt_y = (top_t >> 11) & 1;
  for (int r = 0; r < 32; r++) {
    int row = sy / 8 + r, nty = nt_y;
    while (row >= 30) { row -= 30; nty ^= 1; }
    for (int c = 0; c < 32; c += 2) {
      u8 cell[2];
      for (int k = 0; k < 2; k++) {
        int col = (top_t & 31) + c + k, ntx = (top_t >> 10) & 1;
        if (col >= 32) { col -= 32; ntx ^= 1; }
        const u8 *nt = &ciram[nt_index(0x2000 + (nty << 11) + (ntx << 10))];
        u16 key = r < 30 ? nt[row * 32 + col] | (nt[0x3C0 + (row >> 2) * 8 + (col >> 2)] >> (((row & 2) << 1) | (col & 2)) & 3) << 8 : 0;
        if (ids[key] == 0xFF) {
          if (count == 255) return 0;
          ids[key] = count;
          pairs[count++] = key;
        }
        cell[k] = ids[key];
      }
      // VRAM takes 16 bits at a time.
      *(volatile u16 *)(map + r * 32 + c) = cell[0] | cell[1] << 8;
    }
  }
  for (int id = 0; id < count; id++) {
    u32 t = pairs[id] & 0xFF, pal = pairs[id] >> 8;
    const u8 *src = chr + pages[t >> 6] * 0x400 + (t & 63) * 16;
    volatile u16 *dst = (volatile u16 *)(VRAM + 2 * 0x4000 + id * 64);
    for (int y = 0; y < 8; y++)
      for (int x = 0; x < 8; x += 2) {
        u32 a = (src[y] >> (7 - x) & 1) | (src[8 + y] >> (7 - x) & 1) << 1;
        u32 b = (src[y] >> (6 - x) & 1) | (src[8 + y] >> (6 - x) & 1) << 1;
        dst[y * 4 + x / 2] = (a ? pal * 16 + a : 0) | (b ? pal * 16 + b : 0) << 8;
      }
  }
  for (int p = 0; p < 4; p++) loaded_bg[2][p] = 0xFFFF;  // the third layer's tiles are gone
  return 1;
}

// Frame k of the arrival: smaller and turned, settling on the NES's picture.
static void place_island(int k, int top) {
  int left = MAP_FRAMES - k;                                   // frames to go
  int ease = left * left * 256 / (MAP_FRAMES * MAP_FRAMES);    // 256 at the start, 0 at the end
  int zoom = 256 - ease * 7 / 8;                               // 8.8: the island's size
  int turn = ease * 3 / 2;                                     // 1/256 turns
  int c = sin256(turn + 64), s = sin256(turn);
  int pa = c * 256 / zoom, pb = s * 256 / zoom, pc = -s * 256 / zoom, pd = c * 256 / zoom;
  int cx = SCREEN_W / 2, cy = SCREEN_H / 2;
  int mx = (cx + 8 + top_x) << 8, my = (cy + top) << 8;
  REG16(0x04000020) = pa;
  REG16(0x04000022) = pb;
  REG16(0x04000024) = pc;
  REG16(0x04000026) = pd;
  REG32(0x04000028) = mx - (pa * cx + pb * cy);
  REG32(0x0400002C) = my - (pc * cx + pd * cy);
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
  if (p_loaded && !on_title()) {
    p_loaded = 0;
    loaded_obj[7] = loaded_obj_lower[7] = 0xFF;  // the P's tile is the last page's
  }
  for (int i = 0; i < 8; i++) {
    if (loaded_obj[i] != top_chr[i]) {
      loaded_obj[i] = top_chr[i];
      copy_chr(OBJ_VRAM + i * 0x800, loaded_obj[i]);
    }
  }
  if (palette_dirty) {
    palette_dirty = 0;
    for (int i = 0; i < 16; i++) BG_PAL[(i >> 2) * 16 + (i & 3)] = nes_colors[palette[i & 3 ? i : 0] & 63];
    for (int i = 0; i < 4; i++) BG_PAL[i * 16 + 15] = nes_colors[palette[0] & 63];  // the masks' sky
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
  static int island = -1;  // the arrival's frame, or -1
  if (!on_world_map() || !(ppu_mask & 0x18)) island = -1;
  else if (island == -1 && !parts && status < 0) island = build_island(top) ? 0 : MAP_FRAMES;
  if (island >= 0 && island < MAP_FRAMES) {
    place_island(island++, top);
    BG2CNT = 2 << 2 | 1 << 7 | AFFINE_MAP << 8 | 1 << 14;  // 8-bit tiles, 256x256
    DISPCNT = 0x0001 | 0x0040 | 0x0400;                     // mode 1, the affine layer only
    nt_dirty = 0;
    return;
  }
  int cloud_stage = parallax_stage(parts, status);
  load_bg_pages(0, top_chr, top_ctrl, cloud_stage >= 0);

  int picture_y = ((top_t >> 5) & 31) * 8 + ((top_t >> 12) & 7) + top;
  if (!layer_map_up_to_date(0, top_t & 0x0C1F, picture_y >> 3)) draw_bg(MAP(layer_map[0]), top_t, top, 22);
  BG0VOFS = picture_y & 7;
  BG0HOFS = top_x;
  if (cloud_stage >= 0) {
    // The mask on the third layer, with the picture's map and scroll, and the clouds on
    // the fourth, at half the camera's speed, both behind the sprites behind the picture.
    load_bg_pages(2, top_chr, top_ctrl, 2);
    BG2CNT = 2 << 2 | layer_map[0] << 8 | 3;
    REG16(0x04000018) = top_x;
    REG16(0x0400001A) = picture_y & 7;
    draw_clouds(cloud_stage);
    BG3CNT = 0 << 2 | CLOUD_MAP << 8 | 3;
    int x = ((top_t >> 10) & 1) * 256 + (top_t & 31) * 8 + top_x;
    REG16(0x0400001C) = x >> 1;
    REG16(0x0400001E) = (short)(PAR_STAGE(cloud_stage)[2] | PAR_STAGE(cloud_stage)[3] << 8) + top;
  } else {
    BG3CNT = CHARBLOCK_TEXT << 2 | MAP_TEXT << 8;
    REG16(0x0400001C) = 0;
    REG16(0x0400001E) = TEXT_SCROLL;
  }

  // Windows: inside window 0 is the bottom layer, inside window 1 the next one up,
  // and outside them both the top of the frame.
  u16 enable = 0x0100 | (title ? 0x0800 : 0) | (cloud_stage >= 0 ? 0x0C00 : 0);
  u16 window_on = 0;
  u16 win_in = 0;
  int layer = 1;
  for (int p = 0; p < parts; p++, layer++) {
    struct region *r = &regions[part_line[p]];
    REG16(0x04000008 + layer * 2) = layer << 2 | layer_map[layer] << 8 | 1;
    int t = (r->t & 0x041F) | (r->own_row ? r->t & ~0x041F : top_t & ~0x041F);
    int y = ((t >> 5) & 31) * 8 + ((t >> 12) & 7) + (r->own_row ? top - ((r->line + 7) & ~7) + ((r->line + 7) & ~7) : top);
    load_bg_pages(layer, r->chr, r->ctrl, 0);
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
    load_bg_pages(layer, r->chr, r->ctrl, 0);
    int key = r->t | r->own_row << 16;
    int fine = ((r->own_row ? 0 : status_line) + ((r->t >> 5) & 31) * 8 + ((r->t >> 12) & 7)) & 7;
    if (!layer_map_up_to_date(layer, key, status_line))
      draw_bg(MAP(layer_map[layer]), r->t, r->own_row ? 0 : status_line, status_h / 8 + 1);
    REG16(0x04000010 + layer * 4) = r->x;
    REG16(0x04000012 + layer * 4) = fine - view_h;
    WIN0V = view_h << 8 | SCREEN_H;
    win_in |= 1 << layer | 0x10;
    // In front of the sprites, so one crossing its top edge stays behind it. The status
    // bar's own sprites have priority 0 and stay on top.
    REG16(0x04000008 + layer * 2) = layer << 2 | layer_map[layer] << 8;
    window_on |= 0x2000;
    enable |= 0x100 << layer;
  }
  WIN0H = SCREEN_W;
  WIN1H = SCREEN_W;
  // The top of the frame, sprites and the notices or the clouds and their mask. Inside
  // the sprite window, no sprites.
  WINOUT = cloud_stage >= 0 ? 0x091D : 0x0919;
  nt_dirty = 0;
  int lower_from = -1;
  if (parts || status >= 0) {
    // The status bar's sprites are on the lines after the game's last change of graphics.
    struct region *r = &regions[parts ? part_line[0] : region_count - 1];
    int differ = parts;
    for (int i = 0; i < 8; i++) differ |= r->chr[i] != top_chr[i];
    if (differ) {
      lower_from = parts ? (r->line + 7) & ~7 : status_line;
      for (int i = 0; i < 8; i++) {
        if (loaded_obj_lower[i] != r->chr[i]) {
          loaded_obj_lower[i] = r->chr[i];
          copy_chr(OBJ_VRAM + OBJ_LOWER_TILES * 32 + i * 0x800, loaded_obj_lower[i]);
        }
      }
    }
  }
  draw_sprites(top, lower_from, status_line, view_h, title);
  if (band_from < band_to && !(window_on & 0x4000)) {
    // The portal's lines: everything but the sprites.
    WIN1V = band_from << 8 | band_to;
    win_in |= (cloud_stage >= 0 ? 0x0D : 0x09) << 8;  // the top of the frame and the notices, as outside
    window_on |= 0x4000;
  }
  WININ = win_in;
  if (ppu_mask & 0x18) {
    // The title hides its clouds behind the logo with sprites behind the picture, early in
    // OAM, which on the NES hide later sprites and show the picture there. On the GBA
    // the later sprite would win, so those sprites mark a window without sprites.
    DISPCNT = 0x1040 | enable | window_on | (title ? 0x8000 : 0);
  } else {
    // The GBA's own blanking is white, and the NES's is black.
    DISPCNT = 0;
    BG_PAL[0] = 0;
    palette_dirty = 1;
  }
}
