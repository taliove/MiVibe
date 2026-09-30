/**
 * 功能卡片插画（一）：本地离线识别、豆包云端识别、按键映射。
 * 每个插画在 600×600 面板内居中绘制，play() 在卡片的 4 拍（2 s）内播放。
 */
import {Circle, Line, Node, Rect, Txt} from '@motion-canvas/2d';
import {
  Color, all, createRef, createSignal, delay, easeOutBack, easeOutCubic, linear, loop, sequence,
  type PossibleColor, type ThreadGenerator,
} from '@motion-canvas/core';
import {COLORS, TIDE} from '../../brand/colors.ts';
import {FONT_CJK, FONT_MONO} from '../../brand/fonts.ts';
import {FEATURE_DETAIL} from '../../copy.ts';
import {BEAT} from '../../timing.ts';
import {Remote, keyPoint, type RemoteKey} from '../Remote.tsx';
import {voiceLevel} from '../beat.ts';

export interface Illustration {
  readonly node: Node;
  play(): ThreadGenerator;
}

const ACCENT = TIDE.accentDark;
const CLOUD_WORDS = ['明天', '下午', '三点', '开会'];
const soft = (a: number) => new Color(ACCENT).alpha(a);

/** 小徽标：图标下方的一行说明（中文 + 等宽英文）。 */
function Caption2({y, cn, mono}: {y: number; cn: string; mono: string}): Node {
  return (
    <Node y={y}>
      <Txt y={-18} text={cn} fontFamily={FONT_CJK} fontWeight={700} fontSize={30} fill={COLORS.fg} />
      <Txt y={24} text={mono} fontFamily={FONT_MONO} fontWeight={500} fontSize={22} fill={COLORS.muted} />
    </Node>
  ) as Node;
}

/** 01 本地识别：芯片 + 内部跳动的声波，Wi-Fi 被划掉。 */
export function offlineIllustration(): Illustration {
  const t = createSignal(0);
  const strike = createSignal(0);
  const chip = createRef<Node>();
  const pins = [-60, -20, 20, 60];
  const node = (
    <Node y={-40}>
      <Circle size={420} fill={soft(0.06)} />
      <Node ref={chip}>
        {pins.map(p => (
          <Node>
            <Rect x={p} y={-118} width={14} height={36} radius={4} fill={COLORS.line} />
            <Rect x={p} y={118} width={14} height={36} radius={4} fill={COLORS.line} />
            <Rect x={-118} y={p} width={36} height={14} radius={4} fill={COLORS.line} />
            <Rect x={118} y={p} width={36} height={14} radius={4} fill={COLORS.line} />
          </Node>
        ))}
        <Rect width={210} height={210} radius={32} fill={COLORS.surfaceHi} stroke={ACCENT} lineWidth={3}
          shadowColor={soft(0.5)} shadowBlur={40} />
        {[-44, -15, 15, 44].map((x, i) => (
          <Rect x={x} width={18} radius={9} fill={ACCENT}
            height={() => 24 + 80 * voiceLevel(t() * 1.3, i * 1.3)} />
        ))}
      </Node>
      <Node x={170} y={-150}>
        <Circle size={92} fill={COLORS.bgRaise} stroke={COLORS.line} lineWidth={2} />
        {[34, 22, 10].map((r, i) => (
          <Circle y={14} size={r * 2} startAngle={-135} endAngle={-45} stroke={COLORS.muted}
            lineWidth={5} lineCap={'round'} opacity={i === 2 ? 0 : 1} />
        ))}
        <Circle y={10} size={9} fill={COLORS.muted} />
        <Line points={[[-26, -26], [26, 26]]} stroke={COLORS.error} lineWidth={6} lineCap={'round'} end={strike} />
      </Node>
      <Caption2 y={250} cn={FEATURE_DETAIL.offline[0]} mono={FEATURE_DETAIL.offline[1]} />
    </Node>
  ) as Node;
  return {
    node,
    *play() {
      chip().scale(0.85);
      yield* all(
        t(4, 2, linear),
        chip().scale(1, 0.5, easeOutBack),
        delay(BEAT, strike(1, 0.3, easeOutCubic)),
      );
    },
  };
}

/** 02 云端识别：声波片段从左下飘进云里，识别出的词从右侧一段段流出（流式）。 */
export function cloudIllustration(): Illustration {
  const packets = Array.from({length: 5}, () => createRef<Rect>());
  const words = CLOUD_WORDS.map(() => createRef<Node>());
  const puffs: ReadonlyArray<readonly [number, number, number]> = [
    [-80, 20, 150], [20, -15, 190], [105, 25, 125],
  ];
  const cloudShape = (grow: number, fill: PossibleColor) => (
    <Node>
      {puffs.map(([x, y, d]) => <Circle x={x} y={y} size={d + grow} fill={fill} />)}
      <Rect y={60} width={300 + grow} height={74 + grow} radius={(74 + grow) / 2} fill={fill} />
    </Node>
  );
  const node = (
    <Node y={-40}>
      <Node y={-120}>
        {cloudShape(8, ACCENT)}
        {cloudShape(0, COLORS.surfaceHi)}
        <Txt y={30} text={FEATURE_DETAIL.cloud[1]} fontFamily={FONT_CJK} fontWeight={700} fontSize={46} fill={ACCENT} />
      </Node>
      {packets.map((p, i) => (
        <Rect ref={p} x={-150 + i * 26} y={200} width={14} height={30 + (i % 3) * 16} radius={7}
          fill={ACCENT} opacity={0} />
      ))}
      {CLOUD_WORDS.map((w, i) => (
        <Node ref={words[i]} x={120} y={20 + i * 50} opacity={0}>
          <Rect width={130} height={40} radius={20} fill={soft(0.14)} stroke={soft(0.5)} lineWidth={1.5} />
          <Txt text={w} fontFamily={FONT_CJK} fontWeight={500} fontSize={24} fill={COLORS.fg} />
        </Node>
      ))}
      <Caption2 y={260} cn={FEATURE_DETAIL.cloud[0]} mono={FEATURE_DETAIL.cloud[2]} />
    </Node>
  ) as Node;
  return {
    node,
    *play() {
      const rise = (p: Rect, d: number) =>
        delay(d, loop(3, function* () {
          p.y(200).opacity(0.95);
          yield* all(p.y(-20, 0.55, linear), delay(0.3, p.opacity(0, 0.25)));
        }));
      yield* all(
        ...packets.map((p, i) => rise(p(), i * 0.09)),
        delay(0.45, sequence(0.25, ...words.map(w => {
          w().y(w().y() - 24);
          return all(w().opacity(1, 0.2), w().y(w().y() + 24, 0.3, easeOutCubic));
        }))),
      );
    },
  };
}

/** 03 按键映射：遥控器按键依次点亮，右侧对应的快捷键卡片滑入。 */
export function keysIllustration(): Illustration {
  const keys: RemoteKey[] = ['confirm', 'back', 'menu'];
  const flash = Object.fromEntries(keys.map(k => [k, createSignal(0)])) as Record<RemoteKey, ReturnType<typeof createSignal<number>>>;
  const rows = keys.map(() => createRef<Node>());
  const wires = keys.map(() => createSignal(0));
  const remoteH = 500;
  const unit = remoteH / 290;
  const remoteX = -160;
  const remoteY = 0;
  const rowY = [-150, -30, 90];
  const node = (
    <Node>
      <Node x={remoteX} y={remoteY} rotation={0}>
        <Remote height={remoteH} flash={flash} />
      </Node>
      {keys.map((k, i) => {
        const [kx, ky] = keyPoint(k, unit);
        return (
          <Line
            points={[[remoteX + kx, remoteY + ky], [40, rowY[i]]]} stroke={soft(0.7)} lineWidth={2.5}
            lineDash={[6, 8]} end={wires[i]}
          />
        );
      })}
      {keys.map((_, i) => (
        <Node ref={rows[i]} x={150} y={rowY[i]} opacity={0}>
          <Rect width={210} height={86} radius={18} fill={COLORS.surfaceHi} stroke={COLORS.line} lineWidth={2} />
          <Txt y={-16} text={FEATURE_DETAIL.keys[i][0]} fontFamily={FONT_CJK} fontSize={20} fill={COLORS.muted} />
          <Txt y={16} text={FEATURE_DETAIL.keys[i][1]} fontFamily={FONT_CJK} fontWeight={700} fontSize={30} fill={ACCENT} />
        </Node>
      ))}
    </Node>
  ) as Node;
  return {
    node,
    *play() {
      yield* sequence(
        BEAT,
        ...keys.map((k, i) => all(
          (function* () {
            yield* flash[k](1, 0.08);
            yield* flash[k](0, 0.4);
          })(),
          wires[i](1, 0.25, easeOutCubic),
          delay(0.12, rows[i]().opacity(1, 0.2)),
        )),
      );
    },
  };
}
