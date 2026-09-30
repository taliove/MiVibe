/**
 * 乐器：每个函数渲染一个音符 / 一次击打，返回单声道片段（从 0 秒开始），
 * 由 arrangement.ts 按节拍摆放。音色取向：合成器浪潮 / 极简科技感。
 */
import {
  SR, TAU, adsr, makeBiquad, makeNoise, makeSaw, makeSine, makeSquare, mtof, secToSamples,
} from './dsp.ts';

const buffer = (sec: number) => new Float32Array(secToSamples(sec));

/** 底鼓：正弦 + 指数下滑音高 + 短促点击声。 */
export function kick(punch = 1): Float32Array {
  const out = buffer(0.5);
  const noise = makeNoise(11);
  let phase = 0;
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    const freq = 46 + 110 * Math.exp(-t / 0.03);
    phase += freq / SR;
    const body = Math.sin(TAU * phase) * Math.exp(-t / 0.2);
    const click = noise() * Math.exp(-t / 0.003) * 0.35 * punch;
    out[i] = Math.tanh((body * 1.4 + click) * 1.2);
  }
  return out;
}

/** 踩镲：高通噪声，open 时尾巴更长。 */
export function hat(open = false, seed = 1): Float32Array {
  const len = open ? 0.28 : 0.06;
  const out = buffer(len);
  const noise = makeNoise(seed);
  const hp = makeBiquad('highpass', 0.9);
  const bp = makeBiquad('bandpass', 1.2);
  const tau = open ? 0.09 : 0.018;
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    const n = noise();
    out[i] = (hp(n, 7200) * 0.7 + bp(n, 10500) * 0.5) * Math.exp(-t / tau);
  }
  return out;
}

/** 拍手：三次错开的带通噪声爆发 + 尾音。 */
export function clap(seed = 7): Float32Array {
  const out = buffer(0.35);
  const noise = makeNoise(seed);
  const bp = makeBiquad('bandpass', 1.4);
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    const bursts = [0, 0.011, 0.022].reduce((acc, off) => acc + (t >= off ? Math.exp(-(t - off) / 0.006) : 0), 0);
    const tail = t >= 0.022 ? Math.exp(-(t - 0.022) / 0.09) * 0.6 : 0;
    out[i] = bp(noise(), 1500) * (bursts * 0.6 + tail) * 1.6;
  }
  return out;
}

/** 军鼓（用于冲击前的滚奏）：噪声 + 180 Hz 音体。 */
export function snare(seed = 3): Float32Array {
  const out = buffer(0.22);
  const noise = makeNoise(seed);
  const hp = makeBiquad('highpass', 0.7);
  const sine = makeSine();
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    const tone = sine(185 - 30 * Math.min(1, t / 0.05)) * Math.exp(-t / 0.05) * 0.5;
    out[i] = tone + hp(noise(), 1800) * Math.exp(-t / 0.07) * 0.7;
  }
  return out;
}

/** 贝斯：锯齿 + 次八度方波，低通带滤波包络。 */
export function bass(midi: number, dur: number): Float32Array {
  const out = buffer(dur + 0.08);
  const saw = makeSaw();
  const sub = makeSquare();
  const lp = makeBiquad('lowpass', 1.1);
  const f = mtof(midi);
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    const env = adsr(t, dur, 0.004, 0.12, 0.7, 0.05);
    const cutoff = 220 + 1400 * Math.exp(-t / 0.07);
    const x = saw(f) * 0.6 + sub(f / 2) * 0.45;
    out[i] = lp(x, cutoff) * env;
  }
  return out;
}

/** 拨弦琶音：两只略微失谐的方波，快速关闭的滤波。brightness 0…1。 */
export function pluck(midi: number, brightness = 0.5): Float32Array {
  const out = buffer(0.45);
  const a = makeSquare(0.3);
  const b = makeSaw(0.5);
  const lp = makeBiquad('lowpass', 2);
  const f = mtof(midi);
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    const env = Math.exp(-t / 0.11) * Math.min(1, t / 0.002);
    const cutoff = 500 + (1800 + 4200 * brightness) * Math.exp(-t / 0.06);
    out[i] = lp(a(f) * 0.5 + b(f * 1.004) * 0.4, cutoff) * env;
  }
  return out;
}

/** 铺底和弦：每个音 5 只失谐锯齿（supersaw），慢起音，低通。 */
export function pad(notes: ReadonlyArray<number>, dur: number, cutoff = 1600, attack = 0.35): Float32Array {
  const out = buffer(dur + 1.2);
  const detune = [-0.12, -0.05, 0, 0.06, 0.11];
  const voices = notes.flatMap(n => detune.map((d, k) => ({f: mtof(n + d), osc: makeSaw((k * 0.37) % 1)})));
  const lp = makeBiquad('lowpass', 0.8);
  const norm = 1 / Math.sqrt(voices.length);
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    const env = adsr(t, dur, attack, 1.5, 0.85, 1.0);
    if (env === 0 && t > dur) break;
    let x = 0;
    for (const v of voices) x += v.osc(v.f);
    out[i] = lp(x * norm, cutoff * (0.8 + 0.2 * Math.sin(TAU * 0.25 * t))) * env;
  }
  return out;
}

/** 上升音效：带通噪声 + 上滑锯齿，音量与频率随时间指数上升。 */
export function riser(dur: number): Float32Array {
  const out = buffer(dur);
  const noise = makeNoise(99);
  const bp = makeBiquad('bandpass', 1.6);
  const saw = makeSaw();
  const lp = makeBiquad('lowpass', 1);
  for (let i = 0; i < out.length; i++) {
    const p = i / out.length;
    const curve = Math.pow(p, 2.2);
    const nz = bp(noise(), 300 + 9000 * curve) * 1.3;
    const tone = lp(saw(110 * Math.pow(2, 3 * p)), 800 + 5000 * curve) * 0.25;
    out[i] = (nz + tone) * (0.05 + 0.95 * curve);
  }
  return out;
}

/** 冲击：次低频下坠 + 宽频噪声爆裂，长尾。 */
export function impact(): Float32Array {
  const out = buffer(3.5);
  const noise = makeNoise(1234);
  const lp = makeBiquad('lowpass', 0.7);
  let phase = 0;
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    const freq = 32 + 60 * Math.exp(-t / 0.12);
    phase += freq / SR;
    const boom = Math.sin(TAU * phase) * Math.exp(-t / 0.9);
    const crash = lp(noise(), 1200 + 9000 * Math.exp(-t / 0.35)) * Math.exp(-t / 0.7) * 0.55;
    out[i] = Math.tanh(boom * 1.3) + crash;
  }
  return out;
}

/** 界面提示音：短促正弦「叮」（语音键亮起时）。 */
export function blip(midi: number): Float32Array {
  const out = buffer(0.5);
  const s1 = makeSine();
  const s2 = makeSine();
  const f = mtof(midi);
  for (let i = 0; i < out.length; i++) {
    const t = i / SR;
    const env = Math.min(1, t / 0.003) * Math.exp(-t / 0.12);
    out[i] = (s1(f) * 0.8 + s2(f * 2) * 0.2) * env;
  }
  return out;
}

/** 转场「嗖」声：下滑的带通噪声。 */
export function whoosh(dur = 0.5): Float32Array {
  const out = buffer(dur);
  const noise = makeNoise(42);
  const bp = makeBiquad('bandpass', 2);
  for (let i = 0; i < out.length; i++) {
    const p = i / out.length;
    const env = Math.sin(Math.PI * Math.min(1, p * 1.4)) ** 2;
    out[i] = bp(noise(), 6000 * Math.pow(0.12, p) + 400) * env;
  }
  return out;
}
