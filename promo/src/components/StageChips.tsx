/**
 * 流程段顶部的五个阶段芯片：声音 → 识别 → 纠正 → 改写（可选）→ 输入。
 * activate(i) 点亮第 i 个，并让一个光点沿箭头从上一个芯片跑过来。
 */
import {Circle, Line, Node, Rect, Txt} from '@motion-canvas/2d';
import {
  Color, all, createRef, createSignal, easeInOutCubic, easeOutCubic, sequence,
  type SimpleSignal, type ThreadGenerator,
} from '@motion-canvas/core';
import {COLORS, TIDE} from '../brand/colors.ts';
import {FONT_CJK, FONT_SANS} from '../brand/fonts.ts';

export interface StageCopy {
  readonly cn: string;
  readonly en: string;
  readonly tag?: string;
}

export interface StageChips {
  readonly node: Node;
  enter(): ThreadGenerator;
  activate(index: number): ThreadGenerator;
}

const CHIP_W = 236;
const CHIP_H = 96;
const STEP = 300;

export function createStageChips(stages: ReadonlyArray<StageCopy>, y: number): StageChips {
  const hi: SimpleSignal<number>[] = stages.map(() => createSignal(0));
  const seen: SimpleSignal<number>[] = stages.map(() => createSignal(0));
  const chips: Node[] = [];
  const packets = stages.map(() => createRef<Circle>());
  const xs = stages.map((_, i) => (i - (stages.length - 1) / 2) * STEP);
  const accent = TIDE.accentDark;

  const node = (
    <Node y={y}>
      {xs.slice(0, -1).map((x, i) => (
        <Node>
          <Line
            points={[[x + CHIP_W / 2 + 10, 0], [xs[i + 1] - CHIP_W / 2 - 10, 0]]}
            stroke={() => Color.lerp(COLORS.line, accent, seen[i + 1]())} lineWidth={2.5}
            endArrow arrowSize={9}
          />
          <Circle ref={packets[i]} x={x + CHIP_W / 2} size={12} fill={accent} opacity={0}
            shadowColor={accent} shadowBlur={16} />
        </Node>
      ))}
      {stages.map((s, i) => (
        <Node ref={n => (chips[i] = n)} x={xs[i]} opacity={0}>
          <Rect
            width={CHIP_W} height={CHIP_H} radius={22}
            fill={() => Color.lerp(COLORS.surface, TIDE.accentSoftDark, hi[i]())}
            stroke={() => Color.lerp(COLORS.line, accent, Math.max(hi[i](), 0.45 * seen[i]()))}
            lineWidth={2}
            shadowColor={new Color(accent).alpha(0.45)} shadowBlur={() => 30 * hi[i]()}
          />
          <Txt
            y={-13} text={s.cn} fontFamily={FONT_CJK} fontWeight={700} fontSize={31}
            fill={() => Color.lerp(COLORS.muted, COLORS.fg, Math.max(hi[i](), 0.7 * seen[i]()))}
          />
          <Txt
            y={24} text={s.en} fontFamily={FONT_SANS} fontWeight={500} fontSize={18} letterSpacing={0.6}
            fill={() => Color.lerp(COLORS.faint, accent, hi[i]())}
          />
          {s.tag && (
            <Rect y={-CHIP_H / 2} x={CHIP_W / 2 - 34} width={64} height={28} radius={14}
              fill={COLORS.bgRaise} stroke={COLORS.line} lineWidth={1.5}>
              <Txt text={s.tag} fontFamily={FONT_CJK} fontSize={15} fontWeight={500} fill={COLORS.muted} />
            </Rect>
          )}
        </Node>
      ))}
    </Node>
  ) as Node;

  return {
    node,
    *enter() {
      yield* sequence(
        0.06,
        ...chips.map(c => {
          c.y(16);
          return all(c.opacity(1, 0.35), c.y(0, 0.45, easeOutCubic));
        }),
      );
    },
    *activate(index) {
      const prev = index - 1;
      const moves: ThreadGenerator[] = [hi[index](1, 0.2), seen[index](1, 0.2)];
      if (prev >= 0) {
        const packet = packets[prev]();
        const from = xs[prev] + CHIP_W / 2;
        const to = xs[index] - CHIP_W / 2;
        packet.x(from).opacity(1);
        moves.push(hi[prev](0, 0.25));
        moves.push(
          (function* () {
            yield* packet.x(to, 0.22, easeInOutCubic);
            yield* packet.opacity(0, 0.1);
          })(),
        );
      }
      yield* all(...moves);
    },
  };
}
