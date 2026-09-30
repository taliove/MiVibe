/**
 * 功能卡片外壳：左侧插画面板、右侧文字（标签 · 中文大标题 · 英文副标题），底部 6 段进度条。
 * 每张卡片 4 拍；enter() 在切点那一拍瞬间换上并做 0.3 s 的入场。
 */
import {Node, Rect, Txt} from '@motion-canvas/2d';
import {
  Color, all, createRef, delay, easeOutCubic, type ThreadGenerator,
} from '@motion-canvas/core';
import {COLORS, TIDE} from '../../brand/colors.ts';
import {FONT_CJK, FONT_MONO, FONT_SANS} from '../../brand/fonts.ts';
import type {FeatureCopy} from '../../copy.ts';
import {measureText} from '../measure.ts';

export const PANEL = 600;
const PANEL_X = -420;
const TEXT_X = 20;
const HEAD_MAX_W = 960 - TEXT_X - 110;

export interface FeatureCard {
  readonly node: Node;
  enter(): ThreadGenerator;
}

export function createFeatureCard(
  index: number, total: number, copy: FeatureCopy, illustration: Node,
): FeatureCard {
  const accent = TIDE.accentDark;
  const root = createRef<Node>();
  const panel = createRef<Node>();
  const text = createRef<Node>();
  const tagFont = `600 22px ${FONT_MONO}`;
  const tagW = measureText(copy.tag, tagFont) + 36;
  // 标题右侧至少留 110 px 边距：长标题按可用宽度缩小字号。
  const headSize = Math.min(96, Math.floor(96 * HEAD_MAX_W / measureText(copy.cn, `700 96px ${FONT_CJK}`)));

  const node = (
    <Node ref={root} opacity={0}>
      <Node ref={panel} x={PANEL_X}>
        <Rect
          width={PANEL} height={PANEL} radius={40}
          fill={new Color(COLORS.surface).alpha(0.75)} stroke={COLORS.line} lineWidth={2}
          shadowColor={'rgba(0,0,0,0.45)'} shadowBlur={60} shadowOffset={[0, 20]}
        />
        <Rect width={PANEL} height={PANEL} radius={40} clip>
          {illustration}
        </Rect>
      </Node>
      <Node ref={text} x={TEXT_X}>
        <Txt y={-190} offsetX={-1} text={`0${index + 1} / 0${total}`} fontFamily={FONT_MONO}
          fontSize={24} fontWeight={500} fill={COLORS.faint} letterSpacing={2} />
        <Rect x={tagW / 2} y={-118} width={tagW} height={44} radius={22}
          fill={TIDE.accentSoftDark} stroke={new Color(accent).alpha(0.5)} lineWidth={1.5}>
          <Txt text={copy.tag} fontFamily={FONT_MONO} fontSize={22} fontWeight={600} fill={accent} />
        </Rect>
        <Txt y={-10} offsetX={-1} text={copy.cn} fontFamily={FONT_CJK} fontWeight={700}
          fontSize={headSize} fill={COLORS.fg} />
        <Txt y={92} offsetX={-1} text={copy.en} fontFamily={FONT_SANS} fontWeight={500}
          fontSize={34} fill={COLORS.muted} letterSpacing={0.5} />
      </Node>
    </Node>
  ) as Node;

  return {
    node,
    *enter() {
      root().opacity(1);
      // 切点那一帧就要有画面（从半透明起步），避免硬切时闪一帧空背景。
      panel().scale(0.94).opacity(0.5);
      text().x(TEXT_X + 60).opacity(0.25);
      yield* all(
        panel().scale(1, 0.4, easeOutCubic),
        panel().opacity(1, 0.18),
        delay(0.05, all(text().x(TEXT_X, 0.4, easeOutCubic), text().opacity(1, 0.2))),
      );
    },
  };
}

/** 底部进度条：六段，当前段点亮。 */
export function ProgressBar({total, current}: {total: number; current: () => number}): Node {
  const segW = 120;
  const gap = 14;
  const span = total * segW + (total - 1) * gap;
  return (
    <Node y={430}>
      {Array.from({length: total}, (_, i) => (
        <Rect
          x={-span / 2 + segW / 2 + i * (segW + gap)} width={segW} height={6} radius={3}
          fill={() => (i === current() ? TIDE.accentDark : i < current() ? new Color(TIDE.accentDark).alpha(0.35) : COLORS.line)}
        />
      ))}
    </Node>
  ) as Node;
}
