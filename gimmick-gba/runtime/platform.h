// What core.c needs from the machine it runs on, and what it shows to it.
#ifndef PLATFORM_H
#define PLATFORM_H
#include "cpu.h"

FAR void plat_vblank(void);     // the NES frame has ended
FAR void plat_nmi(void);        // the NMI handler is about to run
FAR u8 plat_pad_read(u16 a);
#ifdef HOST
void plat_step(u32 pc);
#endif

typedef int8_t s8;
FAR void apu_write(u16 a, u8 v);
FAR void fiveb_select(u8 v);
FAR void fiveb_write(u8 v);
void apu_init(u32 hz);
void apu_mix(s8 *out, int n);

FAR void cpu_run(void);
void cpu_power_on(const u8 *on);

extern const u8 *prg, *chr;
extern u8 chr_map[8];
extern u8 ppu_ctrl, ppu_mask, mirror_mode, ppu_x, nt_dirty, palette_dirty;
extern u16 ppu_t;
extern u8 ciram[0x800], palette[32], oam[256];
// The picture at the top of the frame, and the line where it first changed.
extern int split_line;
extern int split_from_top;  // the status bar goes on from the top's rows, not its own
extern u16 top_t, split_t;
extern u8 top_x, top_ctrl, top_chr[8];
extern u8 split_x, split_ctrl, split_chr[8];

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
