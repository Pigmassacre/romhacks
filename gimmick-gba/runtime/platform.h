// What core.c needs from the machine it runs on, and what it shows to it.
#ifndef PLATFORM_H
#define PLATFORM_H
#include "cpu.h"

FAR void plat_vblank(void);     // the NES frame has ended
FAR void plat_nmi(void);        // the NMI handler is about to run
FAR u8 plat_pad_read(u16 a);
#ifdef HOST
void plat_step(u32 pc);
void plat_sync_missed(int nmi, u32 pc, u32 want);
#endif

typedef int8_t s8;
FAR void apu_write(u16 a, u8 v);
FAR void fiveb_select(u8 v);
FAR void fiveb_write(u8 v);
void apu_init(u32 hz);
void apu_mix(s8 *out, int n);

// Replays can take each NMI at the instruction the recording took it, whatever the
// cycle count says, so a heavy frame cannot land a frame apart from the recording's.
typedef struct { u16 pc; u8 a, x, y, s; u16 scratch; } nmi_sync_t;  // scratch: see scratch_sum()

// A sum of low RAM, to tell apart passes through a loop with the same registers.
static inline __attribute__((always_inline)) u16 scratch_sum(const u8 *r) {
  u32 sum = 0;
  for (int i = 0; i < 0x1B; i++) sum = sum * 3 + r[i];  // $1B and $1C are the tour's warps
  return sum;
}
extern const nmi_sync_t *nmi_sync;
extern int nmi_sync_count;

FAR void cpu_run(void);
void cpu_power_on(const u8 *on);

extern const u8 *prg, *chr;
extern u8 chr_map[8];
extern u8 ppu_ctrl, ppu_mask, mirror_mode, ppu_x, nt_dirty, palette_dirty;
extern u16 ppu_t;
extern u8 ciram[0x800], palette[32], oam[256];
// The picture at the top of the frame, and each mid-frame change after it.
extern u16 top_t;
extern u8 top_x, top_ctrl, top_chr[8];
#define MAX_REGIONS 3
struct region {
  int line;      // where it starts
  u16 t;         // the scroll
  u8 x, ctrl, chr[8];
  u8 own_row;    // it set its own row, rather than going on from the top's
};
extern struct region regions[MAX_REGIONS];
extern int region_count;

static inline __attribute__((always_inline)) u16 nt_index(u16 a) {
  a &= 0xFFF;
  switch (mirror_mode & 3) {
    case 0: return a & 0x7FF;                        // vertical
    case 1: return (a & 0x3FF) | (a >> 1 & 0x400);   // horizontal
    case 2: return a & 0x3FF;
    default: return (a & 0x3FF) | 0x400;
  }
}
#endif
