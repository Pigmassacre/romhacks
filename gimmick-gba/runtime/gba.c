// The game on the GBA. It runs one NES frame per GBA frame, and video.c draws at the
// end of each.
//
// With REPLAY defined it plays back the recording instead of the buttons, checks
// RAM against tools/build_gba.py's table, and prints timing and the check's result
// to mGBA's debug log, which tools/run_gba.py reads.
#include "hw.h"

#define FRAME_CYCLES 280896u

extern const u8 rom_prg[], rom_chr[], chr4_data[];

static inline u32 now(void) { return TM2CNT_L | (u32)TM3CNT_L << 16; }

// Sound: a frame is exactly 304 samples at this rate. Finished frames wait in a queue,
// and a VBlank interrupt starts the next, or plays the last again if none is ready.
#define SAMPLES_PER_FRAME 304
#define SAMPLE_PERIOD 924
#define SOUND_QUEUE 4
static s8 sound_buf[SOUND_QUEUE][SAMPLES_PER_FRAME + 16] SLOW_RAM __attribute__((aligned(4)));
static volatile u8 sound_write, sound_read;
static volatile u32 vblank_count;

__attribute__((section(".iwram"), target("arm"))) static void on_vblank(void) {
  DMA1CNT_H = 0;
  if (sound_read != sound_write) sound_read = (sound_read + 1) % SOUND_QUEUE;
  DMA1SAD = (u32)sound_buf[sound_read];
  DMA1CNT_H = 0xB640;  // repeat, 32-bit, in step with the FIFO
  vblank_count++;
  BIOS_IF |= 1;
  IF = 1;
}

static void sound_init(void) {
  apu_init(16777216 / SAMPLE_PERIOD);
  SOUNDCNT_X = 0x80;
  SOUNDCNT_H = 0x0B04;  // FIFO A at full volume, to both speakers, on timer 0
  DMA1DAD = FIFO_A;
  TM0CNT_L = 65536 - SAMPLE_PERIOD;
  TM0CNT_H = 0x80;
  IRQ_VECTOR = (u32)on_vblank;
  DISPSTAT |= 8;
  IE = 1;
  IME = 1;
}

static void wait_vblank(void) {
  __asm__ volatile("swi 5" : : : "r0", "r1", "r2", "r3", "lr", "cc", "memory");
}

#ifdef REPLAY
extern const u8 pad_stream[], pad_stream_end[];
extern const u32 expected[], expected_end[];
extern const struct { u32 nmi; u16 addr, val; } pokes[], pokes_end[];
extern const u8 power_on_ram[];
extern const nmi_sync_t nmi_sync_table[], nmi_sync_end[];
static int poke_next;
static const u8 *pad_at = pad_stream;
struct result {
  u32 magic, frames, cycles_sum, cycles_max, over_budget, checked, first_bad, done, untranslated;
};
volatile struct result result;
static u32 window_gap, window_drawn;
static u32 frame_start, window_sum, window_max, window_over, window_mix, window_draw, last_mix;
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
  while (&pokes[poke_next] < pokes_end && (int)pokes[poke_next].nmi <= nmi_index + 1) {
    if (pokes[poke_next].addr < 0x2000) ram[pokes[poke_next].addr & 0x7FF] = pokes[poke_next].val;
    poke_next++;
  }
  u32 want = expected + nmi_index < expected_end ? expected[nmi_index] : 0;
  nmi_index++;
  if (want) {
#ifndef TIMING_ONLY
    result.checked++;
    if (ram_hash() != want && !result.first_bad) result.first_bad = nmi_index;
#endif
  }
  if (nmi_index % 500 == 0) {
    log_text("nmi=", nmi_index);
    log_text("avg_500=", window_sum / 500);
    log_text("max_500=", window_max);
    log_text("over_500=", result.over_budget - window_over);
    log_text("gap_500=", window_gap);
    log_text("drawn_500=", window_drawn);
    window_gap = window_drawn = 0;
    log_text("mix_500=", window_mix / 500);
    log_text("draw_500=", window_draw / 500);
    window_mix = window_draw = 0;
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
  t += last_mix;
  if (result.frames) {
    result.cycles_sum += t;
    window_sum += t;
    if (t > window_max) window_max = t;
    if (t > result.cycles_max) result.cycles_max = t;
    if (t > FRAME_CYCLES) result.over_budget++;
  }
  result.frames++;
#endif
#ifdef REPLAY
  u32 mix_start = now();
#endif
  u32 next = (sound_write + 1) % SOUND_QUEUE;
  if (next != sound_read) {
    apu_mix(sound_buf[next], SAMPLES_PER_FRAME);
    sound_write = next;
  } else {
    static s8 dropped[SAMPLES_PER_FRAME];  // keep the chips ticking
    apu_mix(dropped, SAMPLES_PER_FRAME);
  }
#ifdef REPLAY
  last_mix = now() - mix_start;
  window_mix += last_mix;
#endif
  // A frame that ran late can skip its drawing and start straight away, to catch up.
  // But only one in a row: the next is always drawn, and if that means falling behind,
  // the game runs slow for a moment, as it does on the NES. Skipping until it had
  // caught up froze the picture for up to a second while the game ran on unseen.
  static u32 nes_frames;
  static int skipped;
  nes_frames++;
  if ((int)(vblank_count - nes_frames) >= 0) {
    if (!skipped) {
      skipped = 1;
#ifdef REPLAY
      frame_start = now();
#endif
      return;
    }
    nes_frames = vblank_count + 1;
  }
  skipped = 0;
  wait_vblank();
#ifdef REPLAY
  // How long the screen went without a new picture, which is what a player sees.
  static u32 last_drawn;
  u32 gap = vblank_count - last_drawn;
  last_drawn = vblank_count;
  if (gap > window_gap) window_gap = gap;
  window_drawn++;
  frame_start = now();  // a frame's load is drawing, the game and the sound
#endif
  video_present();
#ifdef REPLAY
  window_draw += now() - frame_start;
#endif
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
  TM2CNT_L = 0; TM3CNT_L = 0;
  TM3CNT_H = 0x84;   // cascade
  TM2CNT_H = 0x80;
  chr4 = chr4_data;
  video_init();
  prg = rom_prg;
  chr = rom_chr;
  sound_init();
#ifdef REPLAY
  result.magic = 0x47494D4B;
  cpu_power_on(power_on_ram);
#ifndef TIMING_ONLY
  nmi_sync = nmi_sync_table;
  nmi_sync_count = nmi_sync_end - nmi_sync_table;
#endif
  frame_start = now();
#endif
  cpu_run();
  return 0;
}
