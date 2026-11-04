// The game's sound chips in software: the NES's five channels and the Sunsoft 5B's
// three, mixed to 8-bit samples. core.c passes register writes here, and the platform
// asks for one NES frame's samples at a time.
#include "cpu.h"
#include "platform.h"

#define CPU_HZ 1789773u
#define QUARTERS 4
#define OUTPUT_GAIN 280
#ifdef HOST
int apu_only = 0xFF;  // the PC build can render one channel at a time
#endif
#define MAX_SPAN 80   // samples between frame counter ticks, at most: 304 a frame, in 4

static const u8 duty_steps[4] = {0x40, 0x60, 0x78, 0x9F};  // one bit per step
static const u8 length_table[32] = {10,254,20,2,40,4,80,6,160,8,60,10,14,12,26,14,12,16,24,18,48,20,96,22,192,24,72,26,16,28,32,30};
static const u16 noise_periods[16] = {4,8,16,32,64,96,128,160,202,254,380,508,762,1016,2034,4068};
static const u16 dmc_periods[16] = {428,380,340,320,286,254,226,214,190,160,142,128,106,84,72,54};
// The channels' levels relative to each other come from Mesen's mixer, at the volumes
// the game uses: a pulse step is 2 here, a triangle step 3.75, a noise step 2.5, and the 5B's
// levels fall 3 dB a step.
static const u8 fiveb_levels[16] = {0,1,1,2,3,4,5,7,10,14,20,28,39,55,78,110};

struct pulse {
  u32 phase, inc, inverse;
  u16 timer, done_timer;  // done_timer: what inc and inverse were worked out for
  u8 duty, length, env_on, env_loop, env_period, env_div, env_vol, const_vol, start;
  u8 sweep_on, sweep_period, sweep_neg, sweep_shift, sweep_div, sweep_reload, halt, enabled;
};
static struct pulse pulses[2] = {{.done_timer = 0xFFFF}, {.done_timer = 0xFFFF}};

static struct {
  u32 phase, inc;
  u16 timer, done_timer;
  u8 length, linear, linear_reload, linear_flag, control, enabled;
} tri = {.done_timer = 0xFFFF};

static struct {
  u32 accum, inc;
  u16 lfsr;
  u8 mode, length, env_on, env_loop, env_period, env_div, env_vol, const_vol, start, halt, enabled;
} noise = {.lfsr = 1};

static struct {
  u32 accum, inc;
  u16 addr, left, start_addr, start_len;
  u8 level, shift, bits, loop, silent;
} dmc = {.silent = 1};

static struct {
  u8 regs[16], select;
  u32 phase[3], inc[3], inverse[3];
  u16 done_period[3];
  u32 env_phase, env_inc, noise_accum, noise_inc;
  u16 noise_lfsr;
  u8 env_step, env_held, env_hold_level;
} fb = {.noise_lfsr = 1, .done_period = {0xFFFF, 0xFFFF, 0xFFFF}};

static u32 sample_hz = 18157;
static int noise_period = 4;

// Phase runs over 2^32 for one whole wave: 2^32 * (CPU_HZ / divisor) / sample_hz. The
// music writes these registers all the time, mostly with the period they already had,
// so each channel only divides again when its period changes.
static u32 hz_scale;
HOT static u32 period_to_inc(u32 divisor) {
  if (!divisor) return 0;
  u32 scaled = hz_scale / divisor;
  // Faster than the sample rate does not fit, and only noise goes there: a step every
  // sample sounds the same as more of them.
  return scaled >= 1u << 24 ? 0xFFFFFFFFu : scaled << 8;
}

HOT // DPCM's rates are cycles per bit, and can be more than one bit a sample: 16.16 bits.
static u32 dmc_rate(u32 period) {
  return (hz_scale / period) >> 8;
}

static void pulse_update(struct pulse *p) {
  if (p->timer == p->done_timer) return;
  p->done_timer = p->timer;
  p->inc = p->timer >= 8 ? period_to_inc(16u * (p->timer + 1)) : 0;
  p->inverse = p->inc >> 16 ? 65536 / (p->inc >> 16) : 0;
}
HOT static void tri_update(void) {
  if (tri.timer == tri.done_timer) return;
  tri.done_timer = tri.timer;
  tri.inc = tri.timer >= 2 ? period_to_inc(32u * (tri.timer + 1)) : 0;
}
HOT static void fiveb_update(int c) {
  u32 period = fb.regs[c * 2] | (fb.regs[c * 2 + 1] & 15) << 8;
  if (period == fb.done_period[c]) return;
  fb.done_period[c] = period;
  fb.inc[c] = period_to_inc(32u * (period ? period : 1));  // measured in Mesen: 2 cycles a step, 16 steps
  fb.inverse[c] = fb.inc[c] >> 16 ? 65536 / (fb.inc[c] >> 16) : 0;
}

void apu_init(u32 hz) {
  sample_hz = hz;
  hz_scale = (u32)(((uint64_t)CPU_HZ << 24) / hz);
  noise.inc = period_to_inc(noise_periods[0]);
  dmc.inc = dmc_rate(dmc_periods[0]);
  fb.noise_inc = period_to_inc(32);
  fb.env_inc = period_to_inc(32);
}

HOT void apu_write(u16 a, u8 v) {
  if (a >= 0x4000 && a <= 0x4007) {
    struct pulse *p = &pulses[(a - 0x4000) >> 2];
    switch (a & 3) {
      case 0:
        p->duty = v >> 6;
        p->halt = p->env_loop = (v >> 5) & 1;
        p->const_vol = (v >> 4) & 1;
        p->env_period = v & 15;
        break;
      case 1:
        p->sweep_on = v >> 7;
        p->sweep_period = (v >> 4) & 7;
        p->sweep_neg = (v >> 3) & 1;
        p->sweep_shift = v & 7;
        p->sweep_reload = 1;
        break;
      case 2:
        if ((p->timer & 0xFF) != v) {
          p->timer = (p->timer & 0x700) | v;
          pulse_update(p);
        }
        break;
      default:
        if (p->timer >> 8 != (v & 7)) {
          p->timer = (p->timer & 0xFF) | (v & 7) << 8;
          pulse_update(p);
        }
        if (p->enabled) p->length = length_table[v >> 3];
        p->start = 1;
        p->phase = 0;
        break;
    }
  } else if (a == 0x4008) {
    tri.control = v >> 7;
    tri.linear_reload = v & 0x7F;
  } else if (a == 0x400A) {
    if ((tri.timer & 0xFF) != v) {
      tri.timer = (tri.timer & 0x700) | v;
      tri_update();
    }
  } else if (a == 0x400B) {
    if (tri.timer >> 8 != (v & 7)) {
      tri.timer = (tri.timer & 0xFF) | (v & 7) << 8;
      tri_update();
    }
    if (tri.enabled) tri.length = length_table[v >> 3];
    tri.linear_flag = 1;
  } else if (a == 0x400C) {
    noise.halt = noise.env_loop = (v >> 5) & 1;
    noise.const_vol = (v >> 4) & 1;
    noise.env_period = v & 15;
  } else if (a == 0x400E) {
    noise.mode = v >> 7;
    noise.inc = period_to_inc(noise_periods[v & 15]);
    noise_period = noise_periods[v & 15];
  } else if (a == 0x400F) {
    if (noise.enabled) noise.length = length_table[v >> 3];
    noise.start = 1;
  } else if (a == 0x4010) {
    dmc.loop = (v >> 6) & 1;
    dmc.inc = dmc_rate(dmc_periods[v & 15]);
  } else if (a == 0x4011) {
    dmc.level = v & 0x7F;
  } else if (a == 0x4012) {
    dmc.start_addr = 0xC000 + v * 64;
  } else if (a == 0x4013) {
    dmc.start_len = v * 16 + 1;
  } else if (a == 0x4015) {
    pulses[0].enabled = v & 1;
    pulses[1].enabled = (v >> 1) & 1;
    tri.enabled = (v >> 2) & 1;
    noise.enabled = (v >> 3) & 1;
    if (!pulses[0].enabled) pulses[0].length = 0;
    if (!pulses[1].enabled) pulses[1].length = 0;
    if (!tri.enabled) tri.length = 0;
    if (!noise.enabled) noise.length = 0;
    if (v & 0x10) {
      if (!dmc.left) { dmc.addr = dmc.start_addr; dmc.left = dmc.start_len; }
    } else {
      dmc.left = 0;
    }
  }
}

HOT void fiveb_select(u8 v) { fb.select = v & 15; }

HOT void fiveb_write(u8 v) {
  u8 r = fb.select;
  if (fb.regs[r] == v && r != 13) return;
  fb.regs[r] = v;
  if (r < 6) fiveb_update(r >> 1);
  else if (r == 6) fb.noise_inc = period_to_inc(32u * ((v & 31) ? (v & 31) : 1));
  else if (r == 11 || r == 12) {
    u32 period = fb.regs[11] | fb.regs[12] << 8;
    fb.env_inc = period_to_inc(32u * (period ? period : 1));
  } else if (r == 13) {
    fb.env_step = 0;
    fb.env_held = 0;
    fb.env_phase = 0;
  }
}

static void envelope_tick(u8 *start, u8 *div, u8 *vol, u8 period, u8 loop) {
  if (*start) {
    *start = 0;
    *vol = 15;
    *div = period;
  } else if (*div) {
    --*div;
  } else {
    *div = period;
    if (*vol) --*vol;
    else if (loop) *vol = 15;
  }
}

static void quarter_frame(void) {
  for (int i = 0; i < 2; i++) {
    struct pulse *p = &pulses[i];
    envelope_tick(&p->start, &p->env_div, &p->env_vol, p->env_period, p->env_loop);
  }
  envelope_tick(&noise.start, &noise.env_div, &noise.env_vol, noise.env_period, noise.env_loop);
  if (tri.linear_flag) tri.linear = tri.linear_reload;
  else if (tri.linear) tri.linear--;
  if (!tri.control) tri.linear_flag = 0;
}

static void half_frame(void) {
  for (int i = 0; i < 2; i++) {
    struct pulse *p = &pulses[i];
    if (!p->halt && p->length) p->length--;
    if (p->sweep_div == 0 && p->sweep_on && p->sweep_shift) {
      u32 change = p->timer >> p->sweep_shift;
      u32 target = p->sweep_neg ? p->timer - change - (i == 0) : p->timer + change;
      if (target <= 0x7FF && p->timer >= 8) { p->timer = target; pulse_update(p); }
    }
    if (p->sweep_div == 0 || p->sweep_reload) {
      p->sweep_div = p->sweep_period;
      p->sweep_reload = 0;
    } else {
      p->sweep_div--;
    }
  }
  if (!tri.control && tri.length) tri.length--;
  if (!noise.halt && noise.length) noise.length--;
}

// The volume of a pulse at this moment, or 0 when it is silent for any reason.
static inline int pulse_level(struct pulse *p) {
  if (!p->enabled || !p->length || !p->inc) return 0;
  if (!p->sweep_neg && p->sweep_on && (p->timer + (p->timer >> p->sweep_shift)) > 0x7FF) return 0;
  return p->const_vol ? p->env_period : p->env_vol;
}

static inline u32 fiveb_env_level(void) {
  if (fb.env_held) return fb.env_hold_level;
  return (fb.regs[13] & 4) ? fb.env_step : 31 - fb.env_step;
}

// Each channel is added to the buffer in a loop of its own, and a silent one costs
// only its phase. No tables: on the GBA, those would be read from slow ROM.
// A square wave's edges land between samples. Sampling it plainly turns that into
// harsh aliasing, so a sample an edge falls in gets the share of its time spent high.
// The wave has 8 steps, one bit each in shape. Almost every sample is between edges, so
// it works out how many there are until the next step and takes those in one go.
// The squares go into a buffer of changes, not of levels: each square writes only where
// its level changes, and one pass at the end adds them all up. That makes
// a square cost by its edges, not its samples. inverse is 2^16 / (inc >> 16).
#define SET(at, v) do { int v_ = (v); if (v_ != cur) { delta[at] += v_ - cur; cur = v_; } } while (0)
HOT static u32 add_square(short *delta, int n, u32 phase, u32 inc, u32 inverse, int vol, u32 shape) {
  int i = 0, cur = 0;
  while (i < n) {
    // To the next step where the wave changes level, not just the next step: the 5B's
    // squares change twice a wave, and at high notes the steps come every sample or two.
    u32 step = phase >> 29, level = (shape >> step) & 1, same = 1;
    while (same < 7 && ((shape >> ((step + same) & 7)) & 1) == level) same++;
    u32 left = same * 0x20000000 - (phase & 0x1FFFFFFF);
    int run = ((left >> 16) * inverse) >> 16;
    if (run > n - i) run = n - i;
    if (run) {
      SET(i, (shape >> (phase >> 29)) & 1 ? vol : 0);
      i += run;
      phase += inc * run;
      if (i >= n) break;
    }
    u32 was_high = (shape >> (phase >> 29)) & 1;
    phase += inc;
    u32 high = (shape >> (phase >> 29)) & 1;
    if (was_high == high) {
      SET(i, high ? vol : 0);
    } else {
      u32 since = (((phase & 0x1FFFFFFF) >> 16) * inverse) >> 16;
      if (since > 65535) since = 65535;
      SET(i, (vol * (high ? since : 65535 - since)) >> 16);
    }
    i++;
  }
  SET(n, 0);  // delta has n + 1 entries: the square ends with the span
  return phase;
}
#undef SET

#ifdef HOST
// The squares' changes, added up into the buffer, and cleared for the next ones. The
// PC build adds up each channel apart, to play it alone; the GBA in mix_span's last pass.
HOT static void squares_done(short *buf, short *delta, int n) {
  int level = 0;
  for (int i = 0; i < n; i++) {
    level += delta[i];
    delta[i] = 0;
    buf[i] += level;
  }
  delta[n] = 0;
}
#endif

HOT static void mix_pulse(short *delta, int n, struct pulse *p, u32 duty) {
  int vol = pulse_level(p) * 2;
  if (vol && p->inverse) p->phase = add_square(delta, n, p->phase, p->inc, p->inverse, vol, duty);
  else p->phase += p->inc * n;
}

// A stopped triangle holds its level, as a silent DPCM does. Those are steady, and
// each returns its level for mix_span to add along with the output instead.
#define TRI_LEVEL(x) (((x) ^ (((x) >> 4) - 1)) & 15) * 15 >> 2  // 15 down to 0, then up
HOT static int mix_tri(short *buf, int n) {
  u32 phase = tri.phase;
  if (!(tri.enabled && tri.length && tri.linear && tri.inc)) return TRI_LEVEL(phase >> 27);
  u32 inc = tri.inc;
  for (int i = 0; i < n; i++) {
    phase += inc;
    u32 x = phase >> 27;
    buf[i] += TRI_LEVEL(x);
  }
  tri.phase = phase;
  return 0;
}

HOT static void mix_noise(short *buf, int n) {
  int vol = (noise.enabled && noise.length) ? (noise.const_vol ? noise.env_period : noise.env_vol) : 0;
  if (!vol) return;
  u32 accum = noise.accum, inc = noise.inc, lfsr = noise.lfsr, tap = noise.mode ? 6 : 1;
  for (int i = 0; i < n; i++) {
    u32 before = accum;
    accum += inc;
    if (accum < before) {  // it wrapped: at most one step a sample
      u32 bit = (lfsr ^ (lfsr >> tap)) & 1;
      lfsr = lfsr >> 1 | bit << 14;
    }
    if (!(lfsr & 1)) buf[i] += vol * 5 >> 1;
  }
  noise.accum = accum;
  noise.lfsr = lfsr;
}

HOT static int mix_dmc(short *buf, int n) {
  u32 accum = dmc.accum, inc = dmc.inc;
  int level = dmc.level;
  if (!dmc.bits && !dmc.left) {
    dmc.silent = 1;
    dmc.accum = (accum + inc * n) & 0xFFFF;
    return (level * 15) >> 4;
  }
  // In locals: the writes to buf could be any of these for all the compiler knows.
  u32 shift = dmc.shift, bits = dmc.bits, silent = dmc.silent, addr = dmc.addr, left = dmc.left;
  for (int i = 0; i < n; i++) {
    accum += inc;
    for (u32 steps = accum >> 16; steps; steps--) {
      if (!bits) {
        if (left) {
          shift = rd(addr);
          addr = addr == 0xFFFF ? 0x8000 : addr + 1;
          bits = 8;
          silent = 0;
          if (!--left && dmc.loop) { addr = dmc.start_addr; left = dmc.start_len; }
        } else {
          silent = 1;
        }
      }
      if (!silent && bits) {
        // Up 2 for a 1 and down 2 for a 0, unless that leaves 0-127.
        int next = level + (int)((shift & 1) << 2) - 2;
        if ((u32)next <= 127) level = next;
        shift >>= 1;
        bits--;
      }
    }
    accum &= 0xFFFF;
    buf[i] += (level * 15) >> 4;
  }
  dmc.accum = accum;
  dmc.level = level;
  dmc.shift = shift;
  dmc.bits = bits;
  dmc.silent = silent;
  dmc.addr = addr;
  dmc.left = left;
  return 0;
}

HOT static void mix_fiveb(short *buf, short *delta, int n, const u8 *levels) {
  u32 tones = fb.regs[7];
  int any_env = 0;
  for (int c = 0; c < 3; c++) {
    u32 r = fb.regs[8 + c];
    int tone_on = !(tones >> c & 1), noise_on = !(tones >> (c + 3) & 1);
    if (r & 16) { any_env = 1; continue; }
    int vol = levels[r & 15];
    u32 phase = fb.phase[c], inc = fb.inc[c];
    if (vol && !noise_on) {
      if (tone_on && fb.inverse[c]) {
        phase = add_square(delta, n, phase, inc, fb.inverse[c], vol, 0xF0);
      } else if (!tone_on) {
        for (int i = 0; i < n; i++) buf[i] += vol;
      }
    } else if (!vol || !tone_on) {
      phase += inc * n;
    }
    fb.phase[c] = phase;
  }
  // Noise only matters on a channel that is not silent.
  int noisy = 0;
  for (int c = 0; c < 3; c++) {
    u32 r = fb.regs[8 + c];
    if (!(tones >> (c + 3) & 1) && ((r & 16) || levels[r & 15])) noisy = 1;
  }
  if (!any_env && !noisy) return;
  // The envelope and the noise are rare, and only these need sample-by-sample work.
  // What each channel does is the same all span, so it is worked out once, and the
  // state is kept in locals: in the loop, writes to buf could otherwise be the 5B's
  // bytes for all the compiler knows, and it would read them again every sample.
  int count = 0, chan[3], level[3];
  u32 env_mask = 0, tone_mask = 0, noise_mask = 0;
  for (int c = 0; c < 3; c++) {
    u32 r = fb.regs[8 + c];
    int tone_off = tones >> c & 1, noise_off = tones >> (c + 3) & 1;
    if (!(r & 16) && noise_off) continue;
    if (r & 16) env_mask |= 1 << count;
    if (!tone_off) tone_mask |= 1 << count;
    if (!noise_off) noise_mask |= 1 << count;
    level[count] = levels[r & 15];
    chan[count++] = c;
  }
  u32 phase[3], inc[3];
  for (int k = 0; k < count; k++) { phase[k] = fb.phase[chan[k]]; inc[k] = fb.inc[chan[k]]; }
  u32 noise_accum = fb.noise_accum, noise_inc = fb.noise_inc, lfsr = fb.noise_lfsr;
  u32 env_phase = fb.env_phase, env_inc = fb.env_inc;
  int env = levels[fiveb_env_level() >> 1];  // changes only when the envelope steps
  for (int i = 0; i < n; i++) {
    noise_accum += noise_inc;
    if (noise_accum < noise_inc) {
      u32 bit = (lfsr ^ (lfsr >> 3)) & 1;
      lfsr = lfsr >> 1 | bit << 16;
    }
    env_phase += env_inc;
    if (env_phase < env_inc && !fb.env_held) {
      if (++fb.env_step >= 32) {
        u8 shape = fb.regs[13];
        if (!(shape & 8) || (shape & 1)) {
          // Without "continue" it ends at 0. With "hold" it stays where the ramp
          // ended, or at the other end with "alternate".
          int rising = shape & 4, flip = shape & 2;
          fb.env_held = 1;
          fb.env_hold_level = (shape & 8) && ((rising != 0) != (flip != 0)) ? 31 : 0;
        } else {
          fb.env_step = 0;
          if (shape & 2) fb.regs[13] ^= 4;
        }
      }
      env = levels[fiveb_env_level() >> 1];
    }
    int out = 0;
    for (int k = 0; k < count; k++) {
      int bit = 1 << k;
      if (env_mask & bit) phase[k] += inc[k];
      if ((!(tone_mask & bit) || (phase[k] >> 31)) && (!(noise_mask & bit) || (lfsr & 1)))
        out += (env_mask & bit) ? env : level[k];
    }
    buf[i] += out;
  }
  for (int k = 0; k < count; k++) fb.phase[chan[k]] = phase[k];
  fb.noise_accum = noise_accum;
  fb.noise_lfsr = lfsr;
  fb.env_phase = env_phase;
}

// What is in the buffer so far is one channel: keep it only if it is wanted.
#ifdef HOST
#define ONLY(bit) do { static short keep[MAX_SPAN]; \
    for (int i = 0; i < n; i++) { keep[i] = (apu_only & (bit)) ? buf[i] : 0; buf[i] = 0; } \
    for (int i = 0; i < n; i++) total[i] += keep[i]; } while (0)
#define STEADY(bit, level) ((apu_only & (bit)) ? (level) : 0)
#define SQUARES(bit) do { squares_done(buf, delta, n); ONLY(bit); } while (0)
#else
#define ONLY(bit)
#define STEADY(bit, level) (level)
#define SQUARES(bit)  // added up in the last pass, with the 5B's
#endif

HOT __attribute__((noinline)) static void mix_span(s8 *out, int n) {  // kept in fast RAM, not inlined into apu_mix
#ifdef HOST
  short total[MAX_SPAN] = {0};
#endif
  // Cleared a word at a time: n is at most MAX_SPAN, and these have room for it rounded up.
  u32 buf_w[(MAX_SPAN + 1) / 2], delta_w[(MAX_SPAN + 2) / 2];
  short *buf = (short *)buf_w, *delta = (short *)delta_w;
  u8 levels[16], duties[4];
  for (int i = 0; i < 16; i++) levels[i] = fiveb_levels[i];
  for (int i = 0; i < 4; i++) duties[i] = duty_steps[i];
  for (int i = 0; i < (n + 1) / 2; i++) buf_w[i] = 0;
  for (int i = 0; i < (n + 2) / 2; i++) delta_w[i] = 0;
  mix_pulse(delta, n, &pulses[0], duties[pulses[0].duty]);
  SQUARES(1);
  mix_pulse(delta, n, &pulses[1], duties[pulses[1].duty]);
  SQUARES(2);
  int steady = STEADY(4, mix_tri(buf, n));
  ONLY(4);
  mix_noise(buf, n);
  ONLY(8);
  steady += STEADY(16, mix_dmc(buf, n));
  ONLY(16);
  mix_fiveb(buf, delta, n, levels);
  SQUARES(32);  // on the GBA, added up in the last pass instead
  // The NES's output stage blocks DC, so the DPCM level drifting does not push the
  // whole mix up and down. This is the same idea: a high-pass filter, at about 90 Hz.
#ifdef HOST
  for (int i = 0; i < n; i++) buf[i] = total[i];
#endif
  static int dc;
  int level = dc, squares = 0;
  for (int i = 0; i < n; i++) {
    squares += delta[i];
    int in = (buf[i] + squares + steady) << 8;
    level += (in - level) >> 5;
    int s = ((in - level) >> 8) * OUTPUT_GAIN >> 8;
    out[i] = s > 127 ? 127 : s < -128 ? -128 : s;
  }
  dc = level;
}

// One NES frame of samples. The APU's frame counter ticks four times in it.
void apu_mix(s8 *out, int n) {
  static u8 seq;
  int done = 0;
  for (int q = 0; q < QUARTERS; q++) {
    int end = n * (q + 1) / QUARTERS;
    mix_span(out + done, end - done);
    done = end;
    quarter_frame();
    if (seq & 1) half_frame();
    seq++;
  }
}

#ifdef HOST
#include <stdio.h>
// The same fields as APU_LOG in tests/s_record.lua, for tools/compare_sound.py.
void apu_log_line(FILE *f) {
  for (int i = 0; i < 2; i++) {
    struct pulse *p = &pulses[i];
    fprintf(f, "%d %d %d ", p->timer, p->length ? (p->const_vol ? p->env_period : p->env_vol) : 0, p->duty);
  }
  fprintf(f, "%d %d %d %d ", tri.timer, tri.length && tri.linear, noise_period,
          noise.length ? (noise.const_vol ? noise.env_period : noise.env_vol) : 0);
  for (int i = 0; i < 14; i++) fprintf(f, "%d ", fb.regs[i]);
  fprintf(f, "\n");
}
#endif
