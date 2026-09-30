/**
 * 标题组件：大号中文 + 小号英文。reveal() 用遮罩把每行从下往上推入（kinetic type）。
 */
import {Node, Rect, Txt} from '@motion-canvas/2d';
import {all, createRef, delay, easeOutCubic, type ThreadGenerator} from '@motion-canvas/core';
import {COLORS} from '../brand/colors.ts';
import {FONT_CJK, FONT_SANS} from '../brand/fonts.ts';

export interface CaptionProps {
  readonly cn: string;
  readonly en: string;
  readonly x?: number;
  readonly y?: number;
  readonly size?: number;
  /** -1 左对齐，0 居中。 */
  readonly align?: -1 | 0;
  readonly cnFill?: string;
  readonly enFill?: string;
}

export interface Caption {
  readonly node: Node;
  reveal(stagger?: number): ThreadGenerator;
  hide(): ThreadGenerator;
}

const MASK_W = 1900;

export function createCaption({
  cn, en, x = 0, y = 0, size = 120, align = 0, cnFill = COLORS.fg, enFill = COLORS.muted,
}: CaptionProps): Caption {
  const enSize = Math.round(size * 0.3);
  const gap = Math.round(size * 0.28);
  const cnH = size * 1.3;
  const enH = enSize * 1.5;
  const cnTxt = createRef<Txt>();
  const enTxt = createRef<Txt>();
  const root = createRef<Node>();
  const maskX = align === -1 ? MASK_W / 2 : 0;
  const cnY = -(enH + gap) / 2;
  const enY = (cnH + gap) / 2;

  const node = (
    <Node ref={root} x={x} y={y}>
      <Rect y={cnY} x={maskX} width={MASK_W} height={cnH} clip>
        <Txt
          ref={cnTxt} text={cn} x={-maskX} y={cnH} offsetX={align}
          fontFamily={FONT_CJK} fontWeight={700} fontSize={size} fill={cnFill} letterSpacing={size * 0.02}
        />
      </Rect>
      <Rect y={enY} x={maskX} width={MASK_W} height={enH} clip>
        <Txt
          ref={enTxt} text={en} x={-maskX} y={enH} offsetX={align}
          fontFamily={FONT_SANS} fontWeight={500} fontSize={enSize} fill={enFill} letterSpacing={enSize * 0.04}
        />
      </Rect>
    </Node>
  ) as Node;

  return {
    node,
    *reveal(stagger = 0.12) {
      yield* all(
        cnTxt().y(0, 0.5, easeOutCubic),
        delay(stagger, enTxt().y(0, 0.5, easeOutCubic)),
      );
    },
    *hide() {
      yield* all(cnTxt().y(-cnH, 0.3, easeOutCubic), enTxt().y(-enH, 0.3, easeOutCubic));
    },
  };
}
