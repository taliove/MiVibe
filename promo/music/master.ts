/**
 * 母带：响度测量（ITU-R BS.1770 K 加权 + 门限积分）、增益归一、前视限幅、淡出，
 * 以及 16-bit PCM WAV 写出。目标约 -14 LUFS，采样峰值不超过 -1 dBFS。
 */
import {writeFileSync} from 'node:fs';
import {SR, type Stereo, dbToGain, makeBiquad, secToSamples} from './dsp.ts';

/** K 加权：高搁架（+4 dB @ ~1.7 kHz）+ 高通（~38 Hz），系数按 48 kHz 标准给出。 */
function kWeight(x: Float32Array): Float32Array {
  if (SR !== 48000) throw new Error('K-weighting coefficients assume 48 kHz');
  const stages = [
    {b: [1.53512485958697, -2.69169618940638, 1.19839281085285], a: [-1.69065929318241, 0.73248077421585]},
    {b: [1.0, -2.0, 1.0], a: [-1.99004745483398, 0.99007225036621]},
  ];
  let signal = x;
  for (const {b, a} of stages) {
    const out = new Float32Array(signal.length);
    let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (let i = 0; i < signal.length; i++) {
      const y = b[0] * signal[i] + b[1] * x1 + b[2] * x2 - a[0] * y1 - a[1] * y2;
      x2 = x1; x1 = signal[i]; y2 = y1; y1 = y;
      out[i] = y;
    }
    signal = out;
  }
  return signal;
}

/** 门限积分响度（LUFS）。 */
export function integratedLoudness(mix: Stereo): number {
  const l = kWeight(mix.left);
  const r = kWeight(mix.right);
  const block = secToSamples(0.4);
  const hop = secToSamples(0.1);
  const powers: number[] = [];
  for (let start = 0; start + block <= l.length; start += hop) {
    let sum = 0;
    for (let i = start; i < start + block; i++) sum += l[i] * l[i] + r[i] * r[i];
    powers.push(sum / block);
  }
  const lufs = (p: number) => -0.691 + 10 * Math.log10(p);
  const absGated = powers.filter(p => lufs(p) > -70);
  const mean = (ps: number[]) => ps.reduce((a, b) => a + b, 0) / Math.max(ps.length, 1);
  const relThreshold = lufs(mean(absGated)) - 10;
  return lufs(mean(absGated.filter(p => lufs(p) > relThreshold)));
}

export function peakDb(mix: Stereo): number {
  let peak = 0;
  for (let i = 0; i < mix.left.length; i++) {
    peak = Math.max(peak, Math.abs(mix.left[i]), Math.abs(mix.right[i]));
  }
  return 20 * Math.log10(peak || 1e-9);
}

export function applyGain(mix: Stereo, gain: number): Stereo {
  return {left: mix.left.map(v => v * gain), right: mix.right.map(v => v * gain)};
}

/** 前视砖墙限幅：5 ms 前视、50 ms 释放，立体声联动。 */
export function limit(mix: Stereo, ceilingDb = -1): Stereo {
  const ceiling = dbToGain(ceilingDb);
  const n = mix.left.length;
  const look = secToSamples(0.005);
  const release = Math.exp(-1 / (0.05 * SR));
  const need = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const p = Math.max(Math.abs(mix.left[i]), Math.abs(mix.right[i]));
    need[i] = p > ceiling ? ceiling / p : 1;
  }
  // 前视窗口内取最小增益，再平滑释放。
  const left = new Float32Array(n);
  const right = new Float32Array(n);
  let gain = 1;
  for (let i = 0; i < n; i++) {
    let target = 1;
    for (let j = i; j < Math.min(n, i + look); j++) target = Math.min(target, need[j]);
    gain = target < gain ? target : target + (gain - target) * release;
    left[i] = mix.left[i] * gain;
    right[i] = mix.right[i] * gain;
  }
  return {left, right};
}

/** 柔和的总线饱和 + 低切，给混音一点胶水感。 */
export function busGlue(mix: Stereo, drive = 1.2): Stereo {
  const hpL = makeBiquad('highpass', 0.7);
  const hpR = makeBiquad('highpass', 0.7);
  const shape = (v: number) => Math.tanh(v * drive) / Math.tanh(drive);
  return {
    left: mix.left.map(v => shape(hpL(v, 28))),
    right: mix.right.map(v => shape(hpR(v, 28))),
  };
}

/** 从 startSec 起做 lengthSec 的等功率淡出，之后静音。 */
export function fadeOut(mix: Stereo, startSec: number, lengthSec: number): Stereo {
  const start = secToSamples(startSec);
  const len = secToSamples(lengthSec);
  const env = (i: number) => (i < start ? 1 : i >= start + len ? 0 : Math.cos(((i - start) / len) * Math.PI * 0.5));
  return {left: mix.left.map((v, i) => v * env(i)), right: mix.right.map((v, i) => v * env(i))};
}

/** 16-bit 立体声 PCM WAV，TPDF 抖动。 */
export function writeWav(path: string, mix: Stereo): void {
  const n = mix.left.length;
  const data = Buffer.alloc(n * 4);
  let seed = 12345;
  const rand = () => {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    return seed / 4294967296;
  };
  const toInt = (v: number) => {
    const dithered = v * 32767 + (rand() - rand());
    return Math.max(-32768, Math.min(32767, Math.round(dithered)));
  };
  for (let i = 0; i < n; i++) {
    data.writeInt16LE(toInt(mix.left[i]), i * 4);
    data.writeInt16LE(toInt(mix.right[i]), i * 4 + 2);
  }
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + data.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(2, 22); // 立体声
  header.writeUInt32LE(SR, 24);
  header.writeUInt32LE(SR * 4, 28);
  header.writeUInt16LE(4, 32);
  header.writeUInt16LE(16, 34);
  header.write('data', 36);
  header.writeUInt32LE(data.length, 40);
  writeFileSync(path, Buffer.concat([header, data]));
}
