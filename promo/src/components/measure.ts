/**
 * 文字测量：离屏 Canvas 按与场景相同的字体测宽。
 * 浮条等组件需要在换字之前就知道新宽度，才能让宽度弹簧过去而不是跳变。
 */
let ctx: CanvasRenderingContext2D | null = null;

export function measureText(text: string, font: string): number {
  if (!ctx) {
    ctx = document.createElement('canvas').getContext('2d');
    if (!ctx) throw new Error('2D canvas unavailable for text measurement');
  }
  ctx.font = font;
  return ctx.measureText(text).width;
}
