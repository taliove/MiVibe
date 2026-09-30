/**
 * 编曲：把乐器按 src/timing.ts 的节拍表摆到时间线上。
 * 场景切点（段落边界）与这里的段落边界是同一组常量，所以画面天然卡在鼓点上。
 */
import {BEAT, TOTAL_BEATS, THEME_SWITCH_BEATS, RISER_START_BEAT, section} from '../src/timing.ts';
import {type Stereo, makeStereo, mixMono, secToSamples, SR} from './dsp.ts';
import * as inst from './instruments.ts';

/** A 小调 i–VI–III–VII：Am – Fmaj7 – C – G，每小节一个和弦。 */
const PROGRESSION = [
  {pad: [57, 60, 64, 69], bass: 33, arp: [69, 72, 76, 81]},
  {pad: [53, 57, 60, 64], bass: 29, arp: [65, 69, 72, 76]},
  {pad: [55, 60, 64, 67], bass: 36, arp: [67, 72, 76, 79]},
  {pad: [55, 59, 62, 67], bass: 31, arp: [67, 71, 74, 79]},
];
const chordAt = (beat: number) => PROGRESSION[Math.floor(beat / 4) % PROGRESSION.length];

export interface Buses {
  readonly drums: Stereo;
  readonly bass: Stereo;
  readonly pad: Stereo;
  readonly arp: Stereo;
  readonly fx: Stereo;
  /** 底鼓时间点（秒），用于侧链压缩。 */
  readonly kicks: ReadonlyArray<number>;
}

const t = (beat: number) => beat * BEAT;
const range = (from: number, to: number, step = 1) =>
  Array.from({length: Math.max(0, Math.ceil((to - from) / step))}, (_, i) => from + i * step);

const S = {
  intro: section('intro'),
  pipeline: section('pipeline'),
  features: section('features'),
  themes: section('themes'),
  outro: section('outro'),
};
const GROOVE_START = S.pipeline.startBeat;
const FULL_START = S.features.startBeat;
const RISER = S.themes.startBeat + RISER_START_BEAT;
const DROP = S.outro.startBeat;

export function arrange(lengthSec: number): Buses {
  const buses = {
    drums: makeStereo(lengthSec), bass: makeStereo(lengthSec), pad: makeStereo(lengthSec),
    arp: makeStereo(lengthSec), fx: makeStereo(lengthSec),
  };
  const kicks = layDrums(buses.drums);
  layBass(buses.bass);
  layPad(buses.pad);
  layArp(buses.arp);
  layFx(buses.fx);
  return {...buses, kicks};
}

function layDrums(drums: Stereo): number[] {
  const kickSample = inst.kick();
  const kickBeats = [
    ...range(GROOVE_START, RISER + 2), // 冲击前 2 拍收掉底鼓，留出张力
    DROP,
  ];
  kickBeats.forEach(b => mixMono(drums, t(b), kickSample, 0.95));

  const closed = inst.hat(false, 5);
  const open = inst.hat(true, 6);
  range(GROOVE_START, FULL_START).forEach(b => mixMono(drums, t(b + 0.5), closed, 0.32, 0.25));
  range(FULL_START, RISER, 0.25).forEach((b, i) => {
    const offbeat = i % 4 === 2;
    mixMono(drums, t(b), closed, offbeat ? 0.34 : 0.14, i % 2 ? 0.3 : -0.3);
  });
  range(FULL_START, RISER, 4).forEach(b => mixMono(drums, t(b + 3.5), open, 0.2, 0.2));
  mixMono(drums, t(GROOVE_START), open, 0.35, 0);

  const clapSample = inst.clap();
  range(GROOVE_START + 8, RISER).filter(b => b % 2 === 1).forEach(b => mixMono(drums, t(b), clapSample, 0.42, 0.05));

  // 冲击前滚奏：四分 → 八分 → 十六分，力度渐强。
  const sn = inst.snare();
  const roll = [
    ...range(RISER, RISER + 1, 1),
    ...range(RISER + 1, RISER + 2, 0.5),
    ...range(RISER + 2, RISER + 3.5, 0.25),
  ];
  roll.forEach(b => mixMono(drums, t(b), sn, 0.15 + 0.35 * ((b - RISER) / 3.5), 0));
  return kickBeats.map(t);
}

function layBass(bus: Stereo): void {
  range(GROOVE_START, RISER + 2, 0.5).forEach((b, i) => {
    const chord = chordAt(b);
    const note = chord.bass + (i % 4 === 3 ? 12 : 0);
    mixMono(bus, t(b), inst.bass(note, BEAT * 0.42), 0.5);
  });
  mixMono(bus, t(DROP), inst.bass(33, BEAT * 6), 0.55);
}

function layPad(bus: Stereo): void {
  for (let b = 0; b < DROP; b += 4) {
    const chord = chordAt(b);
    const intro = b < GROOVE_START;
    const cutoff = intro ? 700 + 500 * (b / GROOVE_START) : b >= RISER - 4 ? 2600 : 1700;
    mixMono(bus, t(b), inst.pad(chord.pad, t(4) - 0.05, cutoff, intro ? 0.9 : 0.25), intro ? 0.5 : 0.38, 0);
  }
  // 结尾：Am9 长音，从冲击点一直铺到淡出结束。
  const tail = TOTAL_BEATS - DROP;
  mixMono(bus, t(DROP), inst.pad([45, 52, 57, 60, 64, 67, 71], t(tail) - 1, 2400, 0.02), 0.5, 0);
}

function layArp(bus: Stereo): void {
  // 前奏后半进来，八分音符，暗；主段十六分音符，逐段变亮。
  range(S.intro.startBeat + 4, GROOVE_START, 0.5).forEach((b, i) => {
    mixMono(bus, t(b), inst.pluck(chordAt(b).arp[i % 4], 0.05), 0.2, i % 2 ? 0.4 : -0.4);
  });
  range(GROOVE_START, RISER + 2, 0.25).forEach((b, i) => {
    const bright = b < FULL_START ? 0.25 : b < S.themes.startBeat ? 0.5 : 0.75;
    const pattern = [0, 1, 2, 3, 2, 1, 2, 3];
    const note = chordAt(b).arp[pattern[i % pattern.length]];
    mixMono(bus, t(b), inst.pluck(note, bright), 0.16, i % 2 ? 0.45 : -0.45);
  });
  // 结尾：标志声波跳动时，三个高音点缀。
  [81, 76, 72].forEach((note, i) => mixMono(bus, t(DROP + 1 + i), inst.pluck(note, 0.4), 0.2, [-0.3, 0.3, 0][i]));
}

function layFx(bus: Stereo): void {
  // 语音键亮起的一声「叮」，以及进入主段前的小上升。
  mixMono(bus, t(S.intro.startBeat + 2), inst.blip(88), 0.22, 0.1);
  mixMono(bus, t(GROOVE_START - 2), inst.riser(t(2)), 0.3, 0);
  // 功能卡片与主题切换的转场「嗖」声，提前 0.3 s 起，落在切点上。
  const cardCuts = range(FULL_START, S.themes.startBeat, 4);
  const themeCuts = THEME_SWITCH_BEATS.map(b => S.themes.startBeat + b);
  [...cardCuts, ...themeCuts].forEach(b => mixMono(bus, t(b) - 0.3, inst.whoosh(0.45), 0.1, 0));
  // 冲击：上升段 → 冲击。
  mixMono(bus, t(RISER), inst.riser(t(DROP - RISER)), 0.55, 0);
  mixMono(bus, t(DROP), inst.impact(), 0.9, 0);
}

/** 侧链：每个底鼓后按指数恢复的增益曲线（1 = 不压）。 */
export function sidechainCurve(kicks: ReadonlyArray<number>, lengthSec: number, depth: number): Float32Array {
  const n = secToSamples(lengthSec);
  const curve = new Float32Array(n).fill(1);
  for (const k of kicks) {
    const start = secToSamples(k);
    const end = Math.min(n, start + secToSamples(0.45));
    for (let i = start; i < end; i++) {
      const dt = (i - start) / SR;
      const attack = Math.min(1, dt / 0.004);
      curve[i] = Math.min(curve[i], 1 - depth * attack * Math.exp(-dt / 0.11));
    }
  }
  return curve;
}
