/**
 * 实时声波（正在听）：一排圆角柱随确定性「音量」起伏，中间高两边低。
 * collapse 信号 0→1 时所有柱收拢到中心并压扁（对应浮条的签名动作）。
 */
import {Node, Rect} from '@motion-canvas/2d';
import {type PossibleColor, type SimpleSignal} from '@motion-canvas/core';
import {voiceLevel} from './beat.ts';

export interface WaveformProps {
  readonly clock: SimpleSignal<number>;
  readonly collapse: SimpleSignal<number>;
  readonly amp: SimpleSignal<number>;
  readonly color: PossibleColor;
  readonly count?: number;
  readonly barW?: number;
  readonly gap?: number;
  readonly maxH?: number;
  readonly y?: number;
}

export function Waveform({
  clock, collapse, amp, color, count = 48, barW = 10, gap = 9, maxH = 190, y = 0,
}: WaveformProps): Node {
  const span = count * (barW + gap) - gap;
  const bars = Array.from({length: count}, (_, i) => {
    const u = i / (count - 1);
    const x0 = -span / 2 + barW / 2 + i * (barW + gap);
    const bell = Math.exp(-Math.pow((u - 0.5) / 0.28, 2));
    const height = () => {
      const level = voiceLevel(clock() * 1.15, i * 0.37);
      const h = barW + (maxH - barW) * bell * (0.25 + 0.75 * level) * amp();
      return h * (1 - collapse()) + barW * 0.6 * collapse();
    };
    return (
      <Rect
        x={() => x0 * (1 - collapse())} width={barW} height={height} radius={barW / 2}
        fill={color} opacity={() => (0.35 + 0.65 * bell) * (1 - collapse() * 0.4)}
      />
    );
  });
  return (<Node y={y}>{bars}</Node>) as Node;
}
