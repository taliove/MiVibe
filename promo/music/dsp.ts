/**
 * 最小 DSP 工具集：振荡器、包络、双二阶滤波、确定性噪声、混响与延迟。
 * 全部离线逐采样计算，不依赖第三方库；随机数带种子，保证每次生成的 WAV 完全一致。
 */
import {SAMPLE_RATE} from '../src/timing.ts';

export const SR = SAMPLE_RATE;
export const TAU = Math.PI * 2;

export const mtof = (midi: number): number => 440 * Math.pow(2, (midi - 69) / 12);
export const dbToGain = (db: number): number => Math.pow(10, db / 20);
export const secToSamples = (s: number): number => Math.round(s * SR);

/** mulberry32：带种子的伪随机数，输出 [-1, 1)。 */
export function makeNoise(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return (((t ^ (t >>> 14)) >>> 0) / 4294967296) * 2 - 1;
  };
}

/** polyBLEP 残差，用来压低锯齿 / 方波的混叠。 */
function polyBlep(phase: number, dt: number): number {
  if (phase < dt) {
    const t = phase / dt;
    return t + t - t * t - 1;
  }
  if (phase > 1 - dt) {
    const t = (phase - 1) / dt;
    return t * t + t + t + 1;
  }
  return 0;
}

/** 带限锯齿波振荡器；freq 可逐采样变化。 */
export function makeSaw(initialPhase = 0): (freq: number) => number {
  let phase = initialPhase;
  return freq => {
    const dt = freq / SR;
    const out = 2 * phase - 1 - polyBlep(phase, dt);
    phase += dt;
    if (phase >= 1) phase -= 1;
    return out;
  };
}

/** 带限方波振荡器。 */
export function makeSquare(width = 0.5): (freq: number) => number {
  let phase = 0;
  return freq => {
    const dt = freq / SR;
    let out = phase < width ? 1 : -1;
    out += polyBlep(phase, dt);
    const shifted = (phase + 1 - width) % 1;
    out -= polyBlep(shifted, dt);
    phase += dt;
    if (phase >= 1) phase -= 1;
    return out;
  };
}

export function makeSine(): (freq: number) => number {
  let phase = 0;
  return freq => {
    const out = Math.sin(TAU * phase);
    phase += freq / SR;
    if (phase >= 1) phase -= 1;
    return out;
  };
}

export type FilterType = 'lowpass' | 'highpass' | 'bandpass';

/** RBJ 双二阶滤波器；每次调用可以给新的截止频率（扫频用）。 */
export function makeBiquad(type: FilterType, q = 0.707): (x: number, freq: number) => number {
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  let lastFreq = -1;
  let b0 = 0, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
  const update = (freq: number) => {
    const f = Math.min(Math.max(freq, 10), SR * 0.45);
    const w = (TAU * f) / SR;
    const cos = Math.cos(w);
    const alpha = Math.sin(w) / (2 * q);
    const a0 = 1 + alpha;
    if (type === 'lowpass') {
      b0 = (1 - cos) / 2 / a0; b1 = (1 - cos) / a0; b2 = b0;
    } else if (type === 'highpass') {
      b0 = (1 + cos) / 2 / a0; b1 = -(1 + cos) / a0; b2 = b0;
    } else {
      b0 = alpha / a0; b1 = 0; b2 = -alpha / a0;
    }
    a1 = (-2 * cos) / a0;
    a2 = (1 - alpha) / a0;
    lastFreq = freq;
  };
  return (x, freq) => {
    if (freq !== lastFreq) update(freq);
    const y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    return y;
  };
}

/** 线性起音 + 指数衰减到 sustain + 线性释放的 ADSR，t 为音符内时间（秒）。 */
export function adsr(t: number, dur: number, a: number, d: number, s: number, r: number): number {
  if (t < 0) return 0;
  const attack = Math.min(1, t / Math.max(a, 1e-4));
  const held = t < a ? attack : s + (1 - s) * Math.exp(-(t - a) / Math.max(d, 1e-4));
  if (t <= dur) return held;
  const rel = 1 - (t - dur) / Math.max(r, 1e-4);
  return rel > 0 ? held * rel : 0;
}

/** 立体声缓冲。 */
export interface Stereo {
  readonly left: Float32Array;
  readonly right: Float32Array;
}

export function makeStereo(lengthSec: number): Stereo {
  const n = secToSamples(lengthSec);
  return {left: new Float32Array(n), right: new Float32Array(n)};
}

/** 按声像（-1 左 … 1 右，等功率）把单声道片段叠加进立体声缓冲。 */
export function mixMono(target: Stereo, startSec: number, mono: Float32Array, gain: number, pan = 0): void {
  const start = secToSamples(startSec);
  const angle = ((pan + 1) * Math.PI) / 4;
  const gl = Math.cos(angle) * gain * Math.SQRT2;
  const gr = Math.sin(angle) * gain * Math.SQRT2;
  const end = Math.min(mono.length, target.left.length - start);
  for (let i = Math.max(0, -start); i < end; i++) {
    target.left[start + i] += mono[i] * gl;
    target.right[start + i] += mono[i] * gr;
  }
}

export function mixStereo(target: Stereo, source: Stereo, gain: number): void {
  const n = Math.min(target.left.length, source.left.length);
  for (let i = 0; i < n; i++) {
    target.left[i] += source.left[i] * gain;
    target.right[i] += source.right[i] * gain;
  }
}

/** 简化版 Freeverb：8 路梳状 + 4 路全通，左右声道错开延迟做宽度。 */
export function reverb(input: Stereo, roomSize = 0.84, damp = 0.3): Stereo {
  const combs = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617];
  const allpasses = [556, 441, 341, 225];
  const scale = SR / 44100;
  const channel = (x: Float32Array, spread: number): Float32Array => {
    const out = new Float32Array(x.length);
    const combState = combs.map(len => ({buf: new Float32Array(Math.round((len + spread) * scale)), idx: 0, store: 0}));
    const apState = allpasses.map(len => ({buf: new Float32Array(Math.round((len + spread) * scale)), idx: 0}));
    for (let i = 0; i < x.length; i++) {
      const inp = x[i] * 0.015;
      let acc = 0;
      for (const c of combState) {
        const y = c.buf[c.idx];
        c.store = y * (1 - damp) + c.store * damp;
        c.buf[c.idx] = inp + c.store * roomSize;
        c.idx = (c.idx + 1) % c.buf.length;
        acc += y;
      }
      for (const a of apState) {
        const b = a.buf[a.idx];
        a.buf[a.idx] = acc + b * 0.5;
        acc = b - acc;
        a.idx = (a.idx + 1) % a.buf.length;
      }
      out[i] = acc;
    }
    return out;
  };
  return {left: channel(input.left, 0), right: channel(input.right, 23)};
}

/** 乒乓延迟（节拍同步），返回纯湿声。 */
export function pingPong(input: Stereo, delaySec: number, feedback: number, toneHz = 3200): Stereo {
  const d = secToSamples(delaySec);
  const n = input.left.length;
  const left = new Float32Array(n);
  const right = new Float32Array(n);
  const lpL = makeBiquad('lowpass');
  const lpR = makeBiquad('lowpass');
  for (let i = 0; i < n; i++) {
    const fromR = i >= d ? right[i - d] : 0;
    const fromL = i >= d ? left[i - d] : 0;
    const mid = (input.left[i] + input.right[i]) * 0.5;
    left[i] = lpL(mid + fromR * feedback, toneHz);
    right[i] = lpR(fromL * feedback, toneHz);
  }
  return {left, right};
}
