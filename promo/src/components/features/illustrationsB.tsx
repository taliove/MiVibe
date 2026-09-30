/**
 * 功能卡片插画（二）：失败可恢复、输入≠发送、六套主题。
 */
import {Circle, Line, Node, Rect, Txt} from '@motion-canvas/2d';
import {
  Color, all, createRef, createSignal, delay, easeOutBack, easeOutCubic, linear, sequence, waitFor,
} from '@motion-canvas/core';
import {COLORS, THEMES, TIDE} from '../../brand/colors.ts';
import {FONT_CJK, FONT_MONO} from '../../brand/fonts.ts';
import {FEATURE_DETAIL} from '../../copy.ts';
import {BEAT} from '../../timing.ts';
import {AppIcon} from '../Brand.tsx';
import {colorSignal} from '../beat.ts';
import type {Illustration} from './illustrationsA.tsx';

const ACCENT = TIDE.accentDark;

/** 04 失败可恢复：队列里第一条「需处理」轻晃，点「输入到这里」后变成已输入。 */
export function queueIllustration(): Illustration {
  const q = FEATURE_DETAIL.queue;
  const row = createRef<Node>();
  const badgeColor = colorSignal(COLORS.attention);
  const badgeText = createRef<Txt>();
  const button = createRef<Node>();
  const press = createSignal(0);
  const check = createSignal(0);
  const node = (
    <Node y={-10}>
      <Rect y={-55} width={480} height={300} radius={26} fill={COLORS.bgRaise} stroke={COLORS.line} lineWidth={2} />
      <Txt x={-210} y={-172} offsetX={-1} text={q.title} fontFamily={FONT_CJK} fontSize={22}
        fontWeight={500} fill={COLORS.muted} />
      <Node ref={row} y={-105}>
        <Rect width={430} height={96} radius={18} fill={COLORS.surfaceHi}
          stroke={() => new Color(badgeColor() as string).alpha(0.7)} lineWidth={2} />
        <Circle x={-176} size={46} fill={() => new Color(badgeColor() as string).alpha(0.2)} />
        <Rect x={-176} y={-5} width={6} height={18} radius={3} fill={badgeColor} opacity={() => 1 - check()} />
        <Circle x={-176} y={11} size={7} fill={badgeColor} opacity={() => 1 - check()} />
        <Line x={-176} points={[[-9, 1], [-3, 7], [9, -6]]} stroke={COLORS.success} lineWidth={4}
          lineCap={'round'} lineJoin={'round'} end={check} />
        <Txt x={-138} y={-16} offsetX={-1} text={q.items[0]} fontFamily={FONT_CJK} fontWeight={700} fontSize={28} fill={COLORS.fg} />
        <Txt ref={badgeText} x={-138} y={20} offsetX={-1} text={q.pending} fontFamily={FONT_CJK} fontSize={22} fill={badgeColor} />
      </Node>
      <Node y={5}>
        <Rect width={430} height={96} radius={18} fill={COLORS.surfaceHi} stroke={COLORS.line} lineWidth={2} opacity={0.7} />
        <Circle x={-176} size={46} fill={new Color(ACCENT).alpha(0.18)} />
        <Circle x={-176} size={20} startAngle={-90} endAngle={120} stroke={ACCENT} lineWidth={3.5} lineCap={'round'} />
        <Txt x={-138} offsetX={-1} text={q.items[1]} fontFamily={FONT_CJK} fontWeight={500} fontSize={28} fill={COLORS.muted} />
      </Node>
      <Node ref={button} y={172} scale={() => 1 - 0.06 * press()}>
        <Rect width={260} height={72} radius={36} fill={ACCENT} />
        <Txt text={q.action} fontFamily={FONT_CJK} fontWeight={700} fontSize={28} fill={COLORS.ink} />
      </Node>
      <Txt y={262} text={q.footer} fontFamily={FONT_MONO} fontSize={22} fill={COLORS.muted} />
    </Node>
  ) as Node;
  return {
    node,
    *play() {
      // motion-v1「需处理」：横向轻晃一次 ±4 pt、0.4 s。
      const shake = [-8, 8, -6, 4, 0];
      yield* sequence(0.08, ...shake.map(x => row().x(x, 0.08)));
      yield* delay(BEAT * 2 - 0.4 - 0.2, (function* () {
        yield* press(1, 0.08);
        yield* press(0, 0.15);
      })());
      badgeText().text(q.done);
      yield* all(badgeColor(COLORS.success, 0.2), check(1, 0.35, easeOutCubic));
    },
  };
}

/** 05 输入 ≠ 发送：文字进了输入框，但发送按钮不动；回车键被划掉。 */
export function sendIllustration(): Illustration {
  const s = FEATURE_DETAIL.send;
  const typed = createSignal(0);
  const cross = createSignal(0);
  const neq = createRef<Node>();
  const node = (
    <Node y={-30}>
      <Rect y={-80} width={500} height={250} radius={26} fill={COLORS.bgRaise} stroke={COLORS.line} lineWidth={2} />
      {[-150, -110].map((y, i) => (
        <Rect x={i ? 60 : -40} y={y} width={i ? 260 : 300} height={30} radius={15}
          fill={i ? new Color(ACCENT).alpha(0.25) : COLORS.surfaceHi} />
      ))}
      <Rect y={-10} width={440} height={76} radius={20} fill={COLORS.surface} stroke={new Color(ACCENT).alpha(0.6)} lineWidth={2} />
      <Txt x={-200} y={-10} offsetX={-1} text={() => s.text.slice(0, Math.round(typed()))}
        fontFamily={FONT_CJK} fontWeight={500} fontSize={30} fill={COLORS.fg} />
      <Rect x={160} y={-10} width={92} height={50} radius={14} fill={COLORS.line} opacity={0.9}>
        <Txt text={s.button} fontFamily={FONT_CJK} fontWeight={700} fontSize={22} fill={COLORS.muted} />
      </Rect>
      <Node y={140}>
        <Rect x={-110} width={150} height={90} radius={18} fill={COLORS.surfaceHi} stroke={COLORS.line} lineWidth={2}>
          <Txt text={s.key} fontFamily={FONT_MONO} fontWeight={600} fontSize={26} fill={COLORS.muted} />
        </Rect>
        <Line x={-110} points={[[-70, 40], [70, -40]]} stroke={COLORS.error} lineWidth={6} lineCap={'round'} end={cross} />
        <Node ref={neq} x={50} scale={0}>
          <Txt text={'≠'} fontFamily={FONT_MONO} fontWeight={600} fontSize={70} fill={ACCENT} />
        </Node>
        <Rect x={170} width={120} height={90} radius={45} fill={new Color(ACCENT).alpha(0.14)} stroke={ACCENT} lineWidth={2.5}>
          <Txt text={s.button} fontFamily={FONT_CJK} fontWeight={700} fontSize={28} fill={ACCENT} />
        </Rect>
      </Node>
      <Txt y={260} text={s.hint} fontFamily={FONT_CJK} fontWeight={500} fontSize={26} fill={COLORS.muted} />
    </Node>
  ) as Node;
  return {
    node,
    *play() {
      yield* all(
        typed(s.text.length, 0.8, linear),
        delay(BEAT * 2, all(cross(1, 0.25, easeOutCubic), neq().scale(1, 0.35, easeOutBack))),
      );
    },
  };
}

/** 06 六套主题：六枚应用图标环形排开，选中环每半拍跳到下一枚。 */
export function themesIllustration(): Illustration {
  const selected = createSignal(0);
  const icons = THEMES.map(() => createRef<Node>());
  const R = 150;
  const pos = (i: number) => {
    const a = (i / THEMES.length) * Math.PI * 2 - Math.PI / 2;
    return {x: Math.cos(a) * R, y: Math.sin(a) * R};
  };
  const ringX = createSignal(pos(0).x);
  const ringY = createSignal(pos(0).y);
  const node = (
    <Node y={-45}>
      {THEMES.map((t, i) => (
        <Node ref={icons[i]} {...pos(i)} scale={0}>
          <AppIcon size={108} top={t.iconTop} bottom={t.iconBottom} shadow={false} />
        </Node>
      ))}
      <Rect x={ringX} y={ringY} width={132} height={132} radius={32} stroke={COLORS.fg} lineWidth={4} />
      <Txt text={() => THEMES[Math.round(selected())].name} fontFamily={FONT_CJK} fontWeight={700}
        fontSize={44} fill={() => THEMES[Math.round(selected())].accentDark} />
      <Txt y={270} text={THEMES.map(t => t.nameEn).join(' · ')} fontFamily={FONT_MONO} fontSize={19} fill={COLORS.muted} />
    </Node>
  ) as Node;
  return {
    node,
    *play() {
      yield* sequence(0.05, ...icons.map(r => r().scale(1, 0.35, easeOutBack)));
      // 选中环每半拍跳一次（与十六分踩镲同步）。
      for (let i = 1; i < THEMES.length; i++) {
        const p = pos(i);
        selected(i);
        yield* all(ringX(p.x, 0.2, easeOutCubic), ringY(p.y, 0.2, easeOutCubic));
        yield* waitFor(BEAT / 2 - 0.2);
      }
    },
  };
}
