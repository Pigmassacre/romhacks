// The 6502's state and the helpers the translated code uses.
#ifndef CPU_H
#define CPU_H
#include <stdint.h>

typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef u32 (*block_t)(void);

// All of it sits behind one pointer. On the GBA the pointer lives in a register,
// so the translated code never has to load an address from slow ROM to reach it.
struct cpu_state {
  u8 a, x, y, s;
  u8 c, v, i, d;
  u8 n, z;               // n: bit 7 is the flag. z: the flag is set when this is 0.
  u32 cyc_mem;           // the cycle count, where it has no register of its own
  u32 next_event;        // when the next interrupt or other event is due
  u32 block_limit;       // translated blocks only run before this cycle
  const u8 *w6000;       // what reads see at $6000: cartridge RAM or a ROM bank
  u8 *w6000w;            // where writes go: the RAM, or nowhere when it is not mapped
  const u8 *fixed;       // the bank at $E000
  const u8 *window[3];   // the banks at $8000, $A000, $C000
  u8 ram[0x800];
};
extern struct cpu_state cpu_state_store;
#ifdef __arm__
register struct cpu_state *cs asm("r7");
register u32 cyc asm("r6");
#else
#define cs (&cpu_state_store)
#define cyc (cs->cyc_mem)
#endif
#define A (cs->a)
#define X (cs->x)
#define Y (cs->y)
#define S (cs->s)
#define C (cs->c)
#define V (cs->v)
#define I (cs->i)
#define D (cs->d)
#define N (cs->n)
#define Z (cs->z)
#define next_event (cs->next_event)
#define block_limit (cs->block_limit)
#define ram (cs->ram)
#define w6000 (cs->w6000)
#define w6000w (cs->w6000w)
#define fixed (cs->fixed)
#define window (cs->window)
extern const block_t *const code_banks[32];

#ifdef __arm__
#define HOT __attribute__((section(".iwram"), target("arm")))
#define FAR __attribute__((long_call))
#else
#define HOT
#define FAR
#endif

FAR u8 rd(u16 a);
FAR void wr(u16 a, u8 v);
FAR u32 trap(u32 pc);
FAR u32 interp_step(u32 pc);
FAR u32 hot_run(u32 index);
extern const u16 *hot_maps[32];
extern u8 prg_map[3];

// Which fast-RAM block starts at this PC, or 0.
static inline __attribute__((always_inline)) u32 hot_lookup(u32 pc) {
  const u16 *m = hot_maps[pc >= 0xE000 ? 0x1F : prg_map[(pc - 0x8000) >> 13] & 31];
  return m ? m[pc & 0x1FFF] : 0;
}

#define CYC(n) (cyc += (n))
// Test builds count cycles exactly, to stay in step with a recording. The build
// you play leaves out what only moves when an NMI lands on a heavy frame.
#if defined(HOST) || defined(REPLAY)
#define EXACT_TIMING 1
#define FORWARD(label, pc) do { if (cyc < block_limit) goto label; return pc; } while (0)
#define PAGE(base, i) (cyc += (((base) & 0xFF) + (i)) >> 8)
#else
#define FORWARD(label, pc) goto label
#define PAGE(base, i)
#endif
#define PUSH(v) (ram[0x100 + S--] = (v))
#define POP() (ram[0x100 + (u8)++S])
#define IND(z) (ram[(u8)(z)] | ram[(u8)((z) + 1)] << 8)

static inline __attribute__((always_inline)) u8 get_p(void) {
  return (N & 0x80) | (V ? 0x40 : 0) | 0x20 | (D ? 8 : 0) | (I ? 4 : 0) | (Z ? 0 : 2) | (C ? 1 : 0);
}
static inline __attribute__((always_inline)) void set_p(u8 p) {
  N = p;
  V = p & 0x40;
  D = (p >> 3) & 1;
  I = (p >> 2) & 1;
  Z = (p & 2) ? 0 : 1;
  C = p & 1;
}
#define ADC(m) do { u32 v_ = (m); u32 r_ = A + v_ + C; V = (~(A ^ v_) & (A ^ r_)) & 0x80; C = r_ >> 8; A = r_; N = Z = A; } while (0)
#define CMP(r, m) do { u32 r_ = (r) + 0x100 - (u32)(m); C = r_ >> 8; N = Z = (u8)r_; } while (0)

#define ADC_NF(m) do { u32 v_ = (m); u32 r_ = A + v_ + C; V = (~(A ^ v_) & (A ^ r_)) & 0x80; C = r_ >> 8; A = r_; } while (0)
#define CMP_NF(r, m) do { u32 r_ = (r) + 0x100 - (u32)(m); C = r_ >> 8; } while (0)
#define ASL_NF(v_) ({ u8 v = (v_); C = v >> 7; (u8)(v << 1); })
#define LSR_NF(v_) ({ u8 v = (v_); C = v & 1; (u8)(v >> 1); })
#define ROL_NF(v_) ({ u8 v = (v_); u8 c = C; C = v >> 7; (u8)(v << 1 | c); })
#define ROR_NF(v_) ({ u8 v = (v_); u8 c = C; C = v & 1; (u8)(v >> 1 | c << 7); })

static inline __attribute__((always_inline)) u8 ASL(u8 v) { C = v >> 7; v <<= 1; N = Z = v; return v; }
static inline __attribute__((always_inline)) u8 LSR(u8 v) { C = v & 1; v >>= 1; N = Z = v; return v; }
static inline __attribute__((always_inline)) u8 ROL(u8 v) { u8 c = C; C = v >> 7; v = v << 1 | c; N = Z = v; return v; }
static inline __attribute__((always_inline)) u8 ROR(u8 v) { u8 c = C; C = v & 1; v = v >> 1 | c << 7; N = Z = v; return v; }

#endif
