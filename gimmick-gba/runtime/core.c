// The parts of the NES the translated game talks to: FME-7 mapper, PPU registers
// and the loop that runs blocks and takes interrupts. host.c and gba.c supply the
// rest through platform.h.
#include "cpu.h"
#include "platform.h"


struct cpu_state cpu_state_store;
static u8 wram[0x2000] SLOW_RAM;
static u8 no_ram[0x2000] SLOW_RAM;

const u8 *prg, *chr;
u8 prg_map[3];
u8 chr_map[8];
static u8 fme_cmd;
static u8 irq_ctl;
static u32 irq_count, irq_base;  // the counter's value at cycle irq_base
static int irq_pending;
static u32 irq_due = 0xFFFFFFFF;

u8 ppu_ctrl, ppu_mask, mirror_mode, nt_dirty = 1, palette_dirty = 1;
u8 ciram[0x800] SLOW_RAM, palette[32], oam[256] SLOW_RAM;
static u8 ppu_status, ppu_buf, ppu_w, ppu_latch;
static u16 ppu_v;
u16 ppu_t;
u8 ppu_x;
u16 top_t;
u8 top_x, top_ctrl, top_chr[8];
struct region regions[MAX_REGIONS];
int region_count;

// The frame is 29780.5 cycles. vbl_half counts in half cycles.
#define VBL_FIRST 27395u
#define FRAME_HALF 59561u
#define VBL_LENGTH 2273u
#define LINE_THIRDS 341u
static u32 vbl_half = VBL_FIRST * 2;
static u32 vbl_end, render_start;
static int nmi_edge, ppu_w_seen, top_blank_lines = -1;

// In the exact build, code near an event runs one instruction at a time, so that
// interrupts land between the same instructions as on the NES. This is how far ahead
// of an event that starts: the longest a translated block runs without stopping.
#ifdef EXACT_TIMING
#define BLOCK_MARGIN 96
// DPCM playback takes the bus from the CPU for a few cycles a byte.
static u32 dmc_due = 0xFFFFFFFF, dmc_period = 428 * 8, dmc_left, dmc_start_len;
static u8 dmc_loop;
#define DMC_STOLEN 4
#else
#define BLOCK_MARGIN 0
#endif

const nmi_sync_t *nmi_sync;
int nmi_sync_count;
#ifdef EXACT_TIMING
#define SYNC_WINDOW 8000   // how far from the due time an NMI may be moved to its place
static int sync_done, sync_pending;
static u32 sync_due;
#endif

HOT static void set_next_event(void) {
  u32 e = vbl_half / 2;
  if (vbl_end && vbl_end < e) e = vbl_end;
  if (irq_due < e) e = irq_due;
#ifdef EXACT_TIMING
  if (dmc_due < e) e = dmc_due;
#endif
  next_event = nmi_edge ? 0 : e;
  block_limit = next_event > BLOCK_MARGIN ? next_event - BLOCK_MARGIN : 0;
#ifdef EXACT_TIMING
  if (nmi_sync) {
    if (sync_pending) block_limit = 0;
    else if ((ppu_ctrl & 0x80) && vbl_half / 2 - SYNC_WINDOW < block_limit) block_limit = vbl_half / 2 - SYNC_WINDOW;
  }
#endif
}

static inline int rendering(void) {
  return !vbl_end && render_start && cyc >= render_start;
}

// Called after the picture changes mid-frame. Each change that comes well after the
// last starts a new region of the picture, and what the game sets in its first few
// lines is what that region shows.
#define SPLIT_SETTLE_LINES 3
static void mid_frame(void) {
  if (!rendering()) return;
  int line = (cyc - render_start) * 3 / LINE_THIRDS;
  if (!(ppu_mask & 0x18)) {
    // Rendering is still off (the game can keep it off into the frame, for more time
    // to upload): this only sets what the picture will start with.
    top_t = ppu_t; top_x = ppu_x; top_ctrl = ppu_ctrl;
    for (int i = 0; i < 8; i++) top_chr[i] = chr_map[i];
    ppu_w_seen = 0;
    top_blank_lines = line;
    return;
  }
  if (!region_count || line > regions[region_count - 1].line + SPLIT_SETTLE_LINES) {
    if (region_count == MAX_REGIONS) return;
    regions[region_count++].line = line;
  }
  struct region *r = &regions[region_count - 1];
  if (line > r->line + SPLIT_SETTLE_LINES) return;
  // Lines take their column from t. They keep counting rows from the top of the
  // frame unless $2006 moved v.
  r->t = (ppu_t & 0x041F) | ((ppu_w_seen ? ppu_v : top_t) & ~0x041F);
  r->x = ppu_x;
  r->ctrl = ppu_ctrl;
  r->own_row = ppu_w_seen;
  for (int i = 0; i < 8; i++) r->chr[i] = chr_map[i];
}

// Every clock here counts up from power-on and would overflow, so now and then they
// all move back together. This is in vblank, with nothing mid-frame to disturb.
#define REBASE_AFTER 0x20000000u
static void rebase_timers(void) {
  u32 by = REBASE_AFTER - 0x1000;
  cyc -= by;
  vbl_half -= by * 2;
  vbl_end -= by;
  irq_base -= by;
  if (irq_due != 0xFFFFFFFF) irq_due -= by;
#ifdef EXACT_TIMING
  if (dmc_due != 0xFFFFFFFF) dmc_due -= by;
  sync_due -= by;
#endif
}

HOT static void sync_vbl(void) {
#ifdef EXACT_TIMING
  while (cyc >= dmc_due) {
    cyc += DMC_STOLEN;
    if (dmc_left && --dmc_left == 0 && dmc_loop) dmc_left = dmc_start_len;
    dmc_due = dmc_left ? dmc_due + dmc_period : 0xFFFFFFFF;
  }
#endif
  while (cyc >= vbl_half / 2) {
    ppu_status |= 0x80;
    ppu_status &= ~0x40;
    vbl_end = vbl_half / 2 + VBL_LENGTH;
    vbl_half += FRAME_HALF;
    plat_vblank();
    if (cyc > REBASE_AFTER) rebase_timers();
#ifdef EXACT_TIMING
    if (nmi_sync && sync_done < nmi_sync_count) {
      if (ppu_ctrl & 0x80) { sync_pending = 1; sync_due = cyc; }
    } else
#endif
    if (ppu_ctrl & 0x80) nmi_edge = 1;
  }
  if (vbl_end && cyc >= vbl_end) {
    ppu_status &= ~0x80;
    render_start = vbl_end;
    vbl_end = 0;
    region_count = 0;
    ppu_w_seen = 0;
    top_blank_lines = -1;
    top_t = ppu_t; top_x = ppu_x; top_ctrl = ppu_ctrl;
    for (int i = 0; i < 8; i++) top_chr[i] = chr_map[i];
  }
  set_next_event();
}

HOT static u8 ppu_read_data(void) {
  u16 a = ppu_v & 0x3FFF;
  u8 v = ppu_buf;
  if (a < 0x2000) ppu_buf = chr[chr_map[a >> 10] * 0x400 + (a & 0x3FF)];
  else if (a < 0x3F00) ppu_buf = ciram[nt_index(a)];
  else { v = palette[(a & 3) ? a & 31 : a & 15]; ppu_buf = ciram[nt_index(a)]; }
  ppu_v += (ppu_ctrl & 4) ? 32 : 1;
  return v;
}

HOT void ppu_data_write(u8 v) {
  ppu_latch = v;
  u16 a = ppu_v & 0x3FFF;
  if (a >= 0x2000 && a < 0x3F00) { ciram[nt_index(a)] = v; nt_dirty = 1; }
  else if (a >= 0x3F00) { palette[(a & 3) ? a & 31 : a & 15] = v; palette_dirty = 1; }
  ppu_v += (ppu_ctrl & 4) ? 32 : 1;
}

HOT static u32 irq_now(void) {
  // The counter runs down from its value when enabled, wrapping at 16 bits.
  if (!(irq_ctl & 0x80)) return irq_count;
  return (irq_count - (cyc - irq_base)) & 0xFFFF;
}
HOT static void irq_schedule(void) {
  irq_due = 0xFFFFFFFF;
  if ((irq_ctl & 0x81) == 0x81) irq_due = cyc + irq_count + 1;
  set_next_event();
}

HOT static void fme_write(u8 v) {
  u32 c = fme_cmd & 15;
  if (c < 8) { chr_map[c] = v; mid_frame(); }
  else if (c == 8) {
    // Bit 6 picks RAM over ROM, bit 7 enables the RAM.
    if (v & 0x40) { w6000 = wram; w6000w = (v & 0x80) ? wram : no_ram; }
    else { w6000 = prg + (v & 0x3F) * 0x2000; w6000w = no_ram; }
  }
  else if (c <= 11) {
    prg_map[c - 9] = v & 0x3F;
    window[c - 9] = prg + (v & 0x3F) * 0x2000;
  }
  else if (c == 12) mirror_mode = v;
  else if (c == 13) {
    irq_count = irq_now(); irq_base = cyc; irq_ctl = v; irq_pending = 0; irq_schedule();
  } else {
    irq_count = irq_now();
    if (c == 14) irq_count = (irq_count & 0xFF00) | v;
    else irq_count = (irq_count & 0x00FF) | v << 8;
    irq_base = cyc; irq_schedule();
  }
}

HOT u8 rd(u16 a) {
  if (a < 0x2000) return ram[a & 0x7FF];
  if (a >= 0xE000) return fixed[a - 0xE000];
  if (a >= 0x8000) return prg[prg_map[(a - 0x8000) >> 13] * 0x2000 + (a & 0x1FFF)];
  if (a >= 0x6000) return w6000[a - 0x6000];
  if (a < 0x4000) {
    switch (a & 7) {
      case 2: { sync_vbl(); u8 v = (ppu_status & 0xE0) | (ppu_latch & 0x1F); ppu_status &= ~0x80; ppu_w = 0; ppu_latch = v; return v; }
      case 7: return ppu_read_data();
    }
    return 0;
  }
  if (a == 0x4016 || a == 0x4017) return plat_pad_read(a);
  return 0;
}

HOT void wr(u16 a, u8 v) {
  if (a < 0x2000) { ram[a & 0x7FF] = v; return; }
  if (a >= 0x8000) {
    switch (a & 0xE000) {
      case 0x8000: fme_cmd = v; break;
      case 0xA000: fme_write(v); break;
      case 0xC000: fiveb_select(v); break;
      default: fiveb_write(v); break;
    }
    return;
  }
  if (a >= 0x6000) { w6000w[a - 0x6000] = v; return; }
  if (a < 0x4000) {
    ppu_latch = v;
    switch (a & 7) {
      case 0:
        sync_vbl();
        if (!(ppu_ctrl & 0x80) && (v & 0x80) && (ppu_status & 0x80)) { nmi_edge = 1; next_event = block_limit = 0; }
        ppu_ctrl = v;
        ppu_t = (ppu_t & ~0x0C00) | (v & 3) << 10;
        mid_frame();
        break;
      case 1:
        ppu_mask = v;
        if ((v & 0x18) && rendering() && top_blank_lines >= 0) {
          // Rendering starts here, at the row in t. Work out the row at line 0.
          int y = ((ppu_t >> 5) & 31) * 8 + ((ppu_t >> 12) & 7);
          int nt = (ppu_t >> 11) & 1;
          y -= top_blank_lines;
          if (y < 0) { y += 240; nt ^= 1; }
          top_t = (ppu_t & 0x041F) | (y >> 3) << 5 | (y & 7) << 12 | nt << 11;
          top_blank_lines = -1;
        }
        break;
      case 5:
        if (!ppu_w) { ppu_t = (ppu_t & ~0x1F) | v >> 3; ppu_x = v & 7; }
        else ppu_t = (ppu_t & ~0x73E0) | (v & 7) << 12 | (v & 0xF8) << 2;
        ppu_w ^= 1;
        mid_frame();
        break;
      case 6:
        if (!ppu_w) ppu_t = (ppu_t & 0xFF) | (v & 0x3F) << 8;
        else {
          ppu_t = (ppu_t & 0xFF00) | v; ppu_v = ppu_t;
          if (rendering()) ppu_w_seen = 1;
        }
        ppu_w ^= 1;
        mid_frame();
        break;
      case 7: ppu_data_write(v); break;
    }
    return;
  }
  if (a == 0x4014) {
    const u8 *from = &ram[(v & 7) << 8];  // the game only copies from RAM
    if (v >= 0x08) for (int i = 0; i < 256; i++) oam[i] = rd(v << 8 | i);
    else for (int i = 0; i < 256; i++) oam[i] = from[i];
    cyc += 513 + (cyc & 1);
    return;
  }
#ifdef EXACT_TIMING
  if (a == 0x4010) {
    static const u16 rates[16] = {428,380,340,320,286,254,226,214,190,160,142,128,106,84,72,54};
    dmc_period = rates[v & 15] * 8;
    dmc_loop = (v >> 6) & 1;
  } else if (a == 0x4013) {
    dmc_start_len = v * 16 + 1;
  } else if (a == 0x4015) {
    if (v & 0x10) {
      if (!dmc_left) { dmc_left = dmc_start_len; dmc_due = cyc + dmc_period; }
    } else {
      dmc_left = 0;
      dmc_due = 0xFFFFFFFF;
    }
    set_next_event();
  }
#endif
  if (a < 0x4018) apu_write(a, v);
}

HOT static void interrupt(u32 *pc, u16 vector) {
  PUSH(*pc >> 8);
  PUSH(*pc & 0xFF);
  PUSH(get_p() & ~0x10);
  I = 1;
  cyc += 7;
  *pc = fixed[vector - 0xE000] | fixed[vector + 1 - 0xE000] << 8;
}

// RAM's starting values. Without this it starts as zeros.
static const u8 *power_on;
void cpu_power_on(const u8 *on) { power_on = on; }

HOT void cpu_run(void) {
#ifdef __arm__
  cs = &cpu_state_store;
#endif
  S = 0xFD; I = 1; Z = 1;
  if (power_on) {
    for (int i = 0; i < 0x800; i++) ram[i] = power_on[i];
    for (int i = 0; i < 0x2000; i++) wram[i] = power_on[0x800 + i];
  }
  w6000 = prg; w6000w = no_ram;  // at power-on the mapper shows ROM bank 0 at $6000
  fixed = prg + 0x3E000;
  for (int i = 0; i < 3; i++) window[i] = prg;
  u32 pc = fixed[0xFFFC - 0xE000] | fixed[0xFFFD - 0xE000] << 8;
  u32 nmi_vec = fixed[0xFFFA - 0xE000] | fixed[0xFFFB - 0xE000] << 8;
  cyc = 7;
  set_next_event();
  for (;;) {
    if (cyc >= next_event) {
      sync_vbl();
      if (nmi_edge) {
        nmi_edge = 0;
        set_next_event();
#ifdef EXACT_TIMING
        sync_done++;
#endif
        interrupt(&pc, 0xFFFA);
      } else if (!irq_pending && cyc >= irq_due) {
        irq_pending = 1;
        irq_due = 0xFFFFFFFF;
        set_next_event();
      }
    }
    if (irq_pending && !I && pc != nmi_vec) interrupt(&pc, 0xFFFE);
    if (pc == nmi_vec) plat_nmi();
#ifdef HOST
    plat_step(pc);
#endif
#ifndef NO_WAIT_SKIP
    // The game's two wait loops (lda $F0 / bne): nothing changes until an interrupt.
    if ((pc == 0xF29A || pc == 0xF2A3) && ram[0xF0] && cyc < block_limit) cyc = block_limit;
#endif
#ifdef EXACT_TIMING
    if (nmi_sync && sync_done < nmi_sync_count && (sync_pending || ((ppu_ctrl & 0x80) && cyc + SYNC_WINDOW >= vbl_half / 2))) {
      const nmi_sync_t *want = &nmi_sync[sync_done];
      int here = pc == want->pc && A == want->a && X == want->x && Y == want->y && S == (u8)(want->s + 3)
              && scratch_sum(ram) == want->scratch
              && (sync_pending || irq_due > vbl_half / 2);  // an IRQ due first goes first
      if (here || (sync_pending && cyc >= sync_due + SYNC_WINDOW)) {
#ifdef HOST
        if (!here) plat_sync_missed(sync_done, pc, want->pc);
#endif
        if (!sync_pending && cyc < vbl_half / 2) cyc = vbl_half / 2;
        if (!sync_pending) sync_vbl();
        sync_pending = 0;
        nmi_edge = 0;
        sync_done++;
        set_next_event();
        interrupt(&pc, 0xFFFA);
        continue;
      }
    }
    if (cyc >= block_limit) { pc = interp_step(pc); continue; }
#endif
    if (pc >= 0x8000) {
#ifndef INTERP_ONLY
      u32 e = hot_lookup(pc);
      if (e) { pc = hot_run(e); continue; }
#endif
    }
    const block_t *t = pc >= 0xE000 ? code_banks[0x1F]
                     : pc >= 0x8000 ? code_banks[prg_map[(pc - 0x8000) >> 13] & 31] : 0;
    block_t fn = t ? t[pc & 0x1FFF] : 0;
#ifdef INTERP_ONLY
    fn = 0;
#endif
    if (!fn) pc = interp_step(pc); else pc = fn();
  }
}
