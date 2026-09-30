/**
 * 品牌标记与应用图标（矢量重绘，几何见 brand/mark.ts）。
 * barScales：三根声波各自的高度倍数信号（1 = 静止形态），用来做电平跳动。
 */
import {Gradient, Node, Rect} from '@motion-canvas/2d';
import {type PossibleColor, type SignalValue} from '@motion-canvas/core';
import {MARK_BARS, MARK_CORNER_RADII, barCenter, clampBarScale} from '../brand/mark.ts';

const read = <T,>(v: SignalValue<T>): T => (typeof v === 'function' ? (v as () => T)() : v);

export interface MarkProps {
  /** 标记整体边长（像素，对应 100 单位网格）。 */
  readonly size: number;
  readonly fill?: SignalValue<PossibleColor>;
  readonly barScales?: ReadonlyArray<SignalValue<number>>;
  readonly x?: number;
  readonly y?: number;
}

export function BrandMark({size, fill = '#FFFFFF', barScales = [], x = 0, y = 0}: MarkProps): Node {
  const unit = size / 100;
  return (
    <Node x={x} y={y}>
      {MARK_BARS.map((bar, i) => {
        const c = barCenter(bar);
        const scale = i < 3 && barScales[i] !== undefined ? barScales[i] : 1;
        return (
          <Rect
            x={c.x * unit}
            y={c.y * unit}
            width={bar.width * unit}
            height={() => bar.height * unit * clampBarScale(read(scale))}
            radius={MARK_CORNER_RADII[i] * unit}
            fill={fill}
          />
        );
      })}
    </Node>
  ) as Node;
}

export interface IconProps {
  readonly size: number;
  readonly top: SignalValue<PossibleColor>;
  readonly bottom: SignalValue<PossibleColor>;
  readonly barScales?: ReadonlyArray<SignalValue<number>>;
  readonly shadow?: boolean;
}

/** 应用图标：系统风格圆角方块 + 竖直渐变 + 占 64% 的白色标记（同 Scripts/make-icon.swift）。 */
export function AppIcon({size, top, bottom, barScales, shadow = true}: IconProps): Node {
  const fill = () =>
    new Gradient({
      type: 'linear',
      from: [0, -size / 2], to: [0, size / 2],
      stops: [{offset: 0, color: read(top)}, {offset: 1, color: read(bottom)}],
    });
  return (
    <Node>
      <Rect
        width={size} height={size} radius={size * 0.225} smoothCorners
        fill={fill}
        shadowColor={shadow ? 'rgba(0,0,0,0.55)' : 'rgba(0,0,0,0)'}
        shadowBlur={size * 0.18} shadowOffset={[0, size * 0.06]}
      />
      <Rect
        width={size} height={size} radius={size * 0.225} smoothCorners
        stroke={'rgba(255,255,255,0.14)'} lineWidth={Math.max(1, size * 0.006)}
      />
      <BrandMark size={size * 0.64} barScales={barScales} />
    </Node>
  ) as Node;
}
