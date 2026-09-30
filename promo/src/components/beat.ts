/**
 * 场景内的节拍工具：所有动作都按「相对本场景起点的第几拍」排期，
 * 避免逐段 waitFor 累积误差，保证切点与配乐的鼓点重合。
 */
import {
  Color, createSignal, useThread,
  type PossibleColor, type SignalValue, type SimpleSignal, type ThreadGenerator,
} from '@motion-canvas/core';
import {BEAT} from '../timing.ts';

const EPS = 1e-6;

/**
 * 等到本场景第 beat 拍所在的那一帧（已过则立即返回）。
 * 不用 waitFor：它为了让线程时间「领先」会提前一帧返回，动作就会比鼓点早 1 帧。
 */
export function* untilBeat(beat: number): ThreadGenerator {
  yield* untilTime(beat * BEAT);
}

function* untilTime(target: number): ThreadGenerator {
  const thread = useThread();
  while (thread.fixed < target - EPS) yield;
  if (thread.time() < target) thread.time(target);
}

/**
 * 场景收尾：本场景在第 lengthBeats 拍所在帧结束（下一场景的第 0 拍恰好落在这一帧）。
 * 结果由 scripts/check.ts 逐一核对（段落切点与 30 帧/拍网格零偏差）。
 */
export function* endScene(lengthBeats: number): ThreadGenerator {
  yield* untilBeat(lengthBeats);
}

/** 在第 beat 拍执行 task（配合 `yield at(...)` 放进后台线程）。 */
export function* at(beat: number, task: () => ThreadGenerator): ThreadGenerator {
  yield* untilBeat(beat);
  yield* task();
}

/** 场景时钟信号：每帧写入当前场景时间（秒），驱动电平、转圈等连续动画。 */
export function makeClock(): {clock: SimpleSignal<number>; run: () => ThreadGenerator} {
  const clock = createSignal(0);
  function* run(): ThreadGenerator {
    while (true) {
      clock(useThread().time());
      yield;
    }
  }
  return {clock, run};
}

/** 可平滑过渡的颜色信号（主题切换用）。 */
export function colorSignal(initial: SignalValue<PossibleColor>): SimpleSignal<PossibleColor> {
  return createSignal<PossibleColor>(initial, lerpColor);
}

/** 任意可转成颜色的值之间插值（信号插值函数）。 */
export function lerpColor(from: PossibleColor, to: PossibleColor, value: number): Color {
  return Color.lerp(new Color(from), new Color(to), value);
}

/**
 * 确定性的「说话音量」：几个不同频率的正弦叠加出音节起伏，0…1。
 * i 用来给每根声波错开相位（motion-v1：三根声波各自跟随音量，彼此有相位差）。
 */
export function voiceLevel(t: number, i = 0): number {
  const syllable = 0.5 + 0.5 * Math.sin(t * 7.3 + i * 1.9) * Math.sin(t * 2.1 + i * 0.7);
  const wobble = 0.78 + 0.22 * Math.sin(t * 17 + i * 2.1);
  return Math.min(1, Math.max(0, syllable * wobble));
}
