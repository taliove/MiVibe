/**
 * 背景：近黑的潮汐青底色、极淡的网格、一团主题色辉光和四周暗角。
 * glow / accent 都可以是信号，主题段和冲击点会驱动它们。
 */
import {Circle, Grid, Node, Rect} from '@motion-canvas/2d';
import {Color, createSignal, type PossibleColor, type SignalValue} from '@motion-canvas/core';
import {Gradient} from '@motion-canvas/2d';
import {COLORS, TIDE, alpha} from '../brand/colors.ts';

export interface BackdropProps {
  readonly accent?: SignalValue<PossibleColor>;
  readonly glow?: SignalValue<number>;
  readonly glowY?: number;
  readonly grid?: SignalValue<number>;
}

const FALLOFF: ReadonlyArray<readonly [number, number]> = [
  [0, 1], [0.15, 0.85], [0.3, 0.6], [0.45, 0.36], [0.6, 0.18], [0.75, 0.07], [0.9, 0.015], [1, 0],
];

const W = 1920;
const H = 1080;

export function Backdrop({accent = TIDE.accentDark, glow = 1, glowY = -80, grid = 1}: BackdropProps): Node {
  const vignette = new Gradient({
    type: 'radial',
    from: [0, 0], to: [0, 0],
    fromRadius: 380, toRadius: 1150,
    stops: [
      {offset: 0, color: 'rgba(6,11,12,0)'},
      {offset: 1, color: alpha(COLORS.bg, 0.96)},
    ],
  });
  const resolve = <T,>(v: SignalValue<T>) => (typeof v === 'function' ? (v as () => T)() : v);
  const glowFill = () =>
    new Gradient({
      type: 'radial',
      from: [0, 0], to: [0, 0],
      fromRadius: 0, toRadius: 620,
      // 近似高斯衰减，避免线性渐变在暗部出现一圈马赫带。
      stops: FALLOFF.map(([offset, a]) => ({offset, color: new Color(resolve(accent)).alpha(a)})),
    });
  return (
    <Node>
      <Rect width={W} height={H} fill={COLORS.bg} />
      <Circle y={glowY} size={1240} scaleY={0.62} fill={glowFill} opacity={() => 0.16 * resolve(glow)} />
      <Grid
        width={W} height={H} spacing={80}
        stroke={alpha('#22B8C6', 0.055)} lineWidth={1}
        opacity={() => resolve(grid)}
      />
      <Rect width={W} height={H} fill={vignette} />
    </Node>
  ) as Node;
}

/** 便捷：带信号的辉光强度（冲击时闪一下）。 */
export const makeGlow = (initial = 1) => createSignal(initial);
