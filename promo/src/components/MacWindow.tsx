/**
 * macOS 窗口外框（矢量）：深色表面、标题栏与三个红绿灯，children 放内容区。
 * 内容区坐标原点在窗口中心，标题栏高度 titleH。
 */
import {Circle, Node, Rect, Txt, type ComponentChildren} from '@motion-canvas/2d';
import {COLORS} from '../brand/colors.ts';
import {FONT_SANS} from '../brand/fonts.ts';

export interface WindowProps {
  readonly width: number;
  readonly height: number;
  readonly title?: string;
  readonly titleH?: number;
  readonly children?: ComponentChildren;
}

const LIGHTS = ['#FF5F57', '#FEBC2E', '#28C840'];

export function MacWindow({width, height, title = '', titleH = 52, children}: WindowProps): Node {
  const top = -height / 2;
  return (
    <Node>
      <Rect
        width={width} height={height} radius={20} fill={COLORS.surface}
        stroke={'rgba(255,255,255,0.08)'} lineWidth={1.5}
        shadowColor={'rgba(0,0,0,0.6)'} shadowBlur={80} shadowOffset={[0, 30]}
      />
      <Rect
        y={top + titleH / 2} width={width} height={titleH} radius={[20, 20, 0, 0]}
        fill={COLORS.surfaceHi}
      />
      <Rect y={top + titleH} width={width} height={1.5} fill={'rgba(255,255,255,0.06)'} />
      {LIGHTS.map((c, i) => (
        <Circle x={-width / 2 + 30 + i * 26} y={top + titleH / 2} size={15} fill={c} />
      ))}
      <Txt
        y={top + titleH / 2} text={title} fontFamily={FONT_SANS} fontSize={19} fontWeight={600}
        fill={COLORS.muted}
      />
      <Node y={titleH / 2}>{children}</Node>
    </Node>
  ) as Node;
}
