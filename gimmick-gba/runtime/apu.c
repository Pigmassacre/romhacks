// The game's sound chips in software: the NES's five channels and the Sunsoft 5B's
// three, mixed to 8-bit samples. core.c passes register writes here, and the platform
// asks for one NES frame's samples at a time.
#include "cpu.h"
#include "platform.h"

#define CPU_HZ 1789773u
#define QUARTERS 4
#define MAX_SPAN 128  // samples between frame counter ticks, at most

static const u8 duty_steps[4] = {0x40, 0x60, 0x78, 0x9F};  // one bit per step
static const u8 length_table[32] = {10,254,20,2,40,4,80,6,160,8,60,10,14,12,26,14,12,16,24,18,48,20,96,22,192,24,72,26,16,28,32,30};
static const u16 noise_periods[16] = {4,8,16,32,64,96,128,160,202,254,380,508,762,1016,2034,4068};
static const u16 dmc_periods[16] = {428,380,340,320,286,254,226,214,190,160,142,128,106,84,72,54};
// 5B levels fall 3 dB a step, scaled to sit with the NES channels.
static const u8 fiveb_levels[16] = {0,1,1,2,2,3,4,6,8,11,16,22,31,44,62,88};

struct pulse {
  u32 phase, inc;
  u16 timer;
  u8 duty, length, env_on, env_loop, env_period, env_div, env_vol, const_vol, start;
  u8 sweep_on, sweep_period, sweep_neg, sweep_shift, sweep_div, sweep_reload, halt, enabled;
};
static struct pulse pulses[2];

static struct {
  u32 phase, inc;
  u16 timer;
  u8 length, linear, linear_reload, linear_flag, control, enabled;
} tri;

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
  u32 phase[3], inc[3];
  u32 env_phase, env_inc, noise_accum, noise_inc;
  u16 noise_lfsr;
  u8 env_step, env_held, env_hold_level;
} fb = {.noise_lfsr = 1};

static u32 sample_hz = 18157;

static u32 period_to_inc(u32 divisor) {
  // Phase runs over 2^32 for one whole wave: 2^32 * (CPU_HZ / divisor) / sample_hz.
  if (!divisor) return 0;
  u32 per_sample = (CPU_HZ << 8) / divisor;     // waves a second, 24.8
  return (u32)(((uint64_t)per_sample << 24) / sample_hz);
}

static void pulse_update(struct pulse *p) {
  p->inc = p->timer >= 8 ? period_to_inc(16u * (p->timer + 1)) : 0;
}
static void tri_update(void) {
  tri.inc = tri.timer >= 2 ? period_to_inc(32u * (tri.timer + 1)) : 0;
}
static void fiveb_update(int c) {
  u32 period = fb.regs[c * 2] | (fb.regs[c * 2 + 1] & 15) << 8;
  fb.inc[c] = period_to_inc(16u * (period ? period : 1));
}

void apu_init(u32 hz) {
  sample_hz = hz;
  noise.inc = period_to_inc(noise_periods[0]);
  dmc.inc = period_to_inc(dmc_periods[0] * 8);
  fb.noise_inc = period_to_inc(16);
  fb.env_inc = period_to_inc(256);
}

void apu_write(u16 a, u8 v) {
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
        p->timer = (p->timer & 0x700) | v;
        pulse_update(p);
        break;
      default:
        p->timer = (p->timer & 0xFF) | (v & 7) << 8;
        pulse_update(p);
        if (p->enabled) p->length = length_table[v >> 3];
        p->start = 1;
        p->phase = 0;
        break;
    }
  } else if (a == 0x4008) {
    tri.control = v >> 7;
    tri.linear_reload = v & 0x7F;
  } else if (a == 0x400A) {
    tri.timer = (tri.timer & 0x700) | v;
    tri_update();
  } else if (a == 0x400B) {
    tri.timer = (tri.timer & 0xFF) | (v & 7) << 8;
    tri_update();
    if (tri.enabled) tri.length = length_table[v >> 3];
    tri.linear_flag = 1;
  } else if (a == 0x400C) {
    noise.halt = noise.env_loop = (v >> 5) & 1;
    noise.const_vol = (v >> 4) & 1;
    noise.env_period = v & 15;
  } else if (a == 0x400E) {
    noise.mode = v >> 7;
    noise.inc = period_to_inc(noise_periods[v & 15]);
  } else if (a == 0x400F) {
    if (noise.enabled) noise.length = length_table[v >> 3];
    noise.start = 1;
  } else if (a == 0x4010) {
    dmc.loop = (v >> 6) & 1;
    dmc.inc = period_to_inc(dmc_periods[v & 15] * 8u);
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

void fiveb_select(u8 v) { fb.select = v & 15; }

void fiveb_write(u8 v) {
  u8 r = fb.select;
  fb.regs[r] = v;
  if (r < 6) fiveb_update(r >> 1);
  else if (r == 6) fb.noise_inc = period_to_inc(16u * ((v & 31) ? (v & 31) : 1));
  else if (r == 11 || r == 12) {
    u32 period = fb.regs[11] | fb.regs[12] << 8;
    fb.env_inc = period_to_inc(16u * (period ? period : 1));
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
HOT static void mix_pulse(short *buf, int n, struct pulse *p, u32 duty) {
  u32 phase = p->phase, inc = p->inc;
  int vol = pulse_level(p) * 2;
  if (vol) {
    for (int i = 0; i < n; i++) {
      phase += inc;
      if ((duty >> (phase >> 29)) & 1) buf[i] += vol;
    }
  } else {
    phase += inc * n;
  }
  p->phase = phase;
}

HOT static void mix_tri(short *buf, int n) {
  u32 phase = tri.phase;
  u32 inc = tri.enabled && tri.length && tri.linear ? tri.inc : 0;
  for (int i = 0; i < n; i++) {
    phase += inc;
    u32 x = phase >> 27;
    buf[i] += (x < 16 ? 15 - x : x - 16) * 2;
  }
  tri.phase = phase;
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
    if (!(lfsr & 1)) buf[i] += vol;
  }
  noise.accum = accum;
  noise.lfsr = lfsr;
}

HOT static void mix_dmc(short *buf, int n) {
  u32 accum = dmc.accum, inc = dmc.inc;
  int level = dmc.level;
  for (int i = 0; i < n; i++) {
    u32 before = accum;
    accum += inc;
    if (accum < before) {
      if (!dmc.bits) {
        if (dmc.left) {
          dmc.shift = rd(dmc.addr);
          dmc.addr = dmc.addr == 0xFFFF ? 0x8000 : dmc.addr + 1;
          dmc.bits = 8;
          dmc.silent = 0;
          if (!--dmc.left && dmc.loop) { dmc.addr = dmc.start_addr; dmc.left = dmc.start_len; }
        } else {
          dmc.silent = 1;
        }
      }
      if (!dmc.silent && dmc.bits) {
        if (dmc.shift & 1) { if (level <= 125) level += 2; }
        else if (level >= 2) level -= 2;
        dmc.shift >>= 1;
        dmc.bits--;
      }
    }
    buf[i] += (level * 3) >> 3;
  }
  dmc.accum = accum;
  dmc.level = level;
}

HOT static void mix_fiveb(short *buf, int n, const u8 *levels) {
  u32 tones = fb.regs[7];
  int any_env = 0;
  for (int c = 0; c < 3; c++) {
    u32 r = fb.regs[8 + c];
    int tone_on = !(tones >> c & 1), noise_on = !(tones >> (c + 3) & 1);
    if (r & 16) { any_env = 1; continue; }
    int vol = levels[r & 15];
    u32 phase = fb.phase[c], inc = fb.inc[c];
    if (vol && !noise_on) {
      if (tone_on) {
        for (int i = 0; i < n; i++) { phase += inc; if (phase >> 31) buf[i] += vol; }
      } else {
        for (int i = 0; i < n; i++) buf[i] += vol;
      }
    } else if (!vol || !tone_on) {
      phase += inc * n;
    }
    fb.phase[c] = phase;
  }
  int noisy = !((tones >> 3) & (tones >> 4) & (tones >> 5) & 1);
  if (!any_env && !noisy) return;
  // The envelope and the noise are rare, and only these need sample-by-sample work.
  for (int i = 0; i < n; i++) {
    fb.noise_accum += fb.noise_inc;
    if (fb.noise_accum < fb.noise_inc) {
      u32 bit = (fb.noise_lfsr ^ (fb.noise_lfsr >> 3)) & 1;
      fb.noise_lfsr = fb.noise_lfsr >> 1 | bit << 16;
    }
    fb.env_phase += fb.env_inc;
    if (fb.env_phase < fb.env_inc && !fb.env_held) {
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
    }
    int env = levels[fiveb_env_level() >> 1];
    for (int c = 0; c < 3; c++) {
      u32 r = fb.regs[8 + c];
      int tone_off = tones >> c & 1, noise_off = tones >> (c + 3) & 1;
      if (!(r & 16) && noise_off) continue;
      if (r & 16) fb.phase[c] += fb.inc[c];
      if ((tone_off || (fb.phase[c] >> 31)) && (noise_off || (fb.noise_lfsr & 1)))
        buf[i] += (r & 16) ? env : levels[r & 15];
    }
  }
}

HOT static void mix_span(s8 *out, int n) {
  short buf[MAX_SPAN];
  u8 levels[16], duties[4];
  for (int i = 0; i < 16; i++) levels[i] = fiveb_levels[i];
  for (int i = 0; i < 4; i++) duties[i] = duty_steps[i];
  for (int i = 0; i < n; i++) buf[i] = 0;
  mix_pulse(buf, n, &pulses[0], duties[pulses[0].duty]);
  mix_pulse(buf, n, &pulses[1], duties[pulses[1].duty]);
  mix_tri(buf, n);
  mix_noise(buf, n);
  mix_dmc(buf, n);
  mix_fiveb(buf, n, levels);
  for (int i = 0; i < n; i++) {
    int s = (buf[i] - 58) * 5 >> 2;
    out[i] = s > 127 ? 127 : s < -128 ? -128 : s;
  }
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
