/**
 * 品牌标记几何：逐字移植自 Sources/MiVibeCore/Core/BrandMark.swift。
 *
 * 三根声波接一个文本光标（寓意「声音变成文字」），100×100 网格。
 * Swift 侧是 y 向上的 CoreGraphics 坐标；这里的场景坐标 y 向下，
 * 所以绘制时对 y 做 100 - (y + h) 翻转，形状本身关于 y=50 对称，结果一致。
 */

export interface MarkRect {
  readonly x: number;
  readonly y: number;
  readonly width: number;
  readonly height: number;
}

/** 顺序：三根声波 → 光标柱 → 两条衬线。 */
export const MARK_BARS: ReadonlyArray<MarkRect> = [
  {x: 17, y: 40, width: 9, height: 20},
  {x: 31, y: 28, width: 9, height: 44},
  {x: 45, y: 36, width: 9, height: 28},
  {x: 66, y: 21, width: 8, height: 58},
  {x: 59, y: 18, width: 22, height: 7},
  {x: 59, y: 75, width: 22, height: 7},
];

export const MARK_CORNER_RADII: ReadonlyArray<number> = [4.5, 4.5, 4.5, 4, 3.5, 3.5];

/** 声波柱允许的最大放大倍数（中间柱 44 × 1.25 = 55，仍矮于光标柱 58）。 */
export const MARK_MAX_BAR_SCALE = 1.25;

/** 每根柱在「以网格中心为原点、y 向下」的坐标系里的中心点。 */
export function barCenter(rect: MarkRect): {x: number; y: number} {
  const flippedY = 100 - (rect.y + rect.height);
  return {x: rect.x + rect.width / 2 - 50, y: flippedY + rect.height / 2 - 50};
}

export function clampBarScale(s: number): number {
  return Math.min(Math.max(s, 0), MARK_MAX_BAR_SCALE);
}
