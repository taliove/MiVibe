/**
 * 浮条（矢量重绘，动效依据 .scratch/mivibe/design/motion-v1.html）：
 * 正在听（三根声波随音量起伏）→ 签名动作 420 ms（声波收拢、圆弧画入并以 1.2 s/圈转动）
 * → 正在改写（底色填满、白色圆弧、四角星）→ 已输入（圆弧合拢、成功绿、对勾描线）。
 */
import {Circle, Line, Node, Rect, Txt} from '@motion-canvas/2d';
import {
  Color, all, createRef, createSignal, delay, easeInOutCubic, easeOutBack, easeOutCubic,
  type PossibleColor, type SignalValue, type SimpleSignal, type ThreadGenerator,
} from '@motion-canvas/core';
import {COLORS} from '../brand/colors.ts';
import {FONT_SANS} from '../brand/fonts.ts';
import {colorSignal, voiceLevel} from './beat.ts';
import {measureText} from './measure.ts';

const read = <T,>(v: SignalValue<T>): T => (typeof v === 'function' ? (v as () => T)() : v);

export interface FloatBarOptions {
  readonly accent: SignalValue<PossibleColor>;
  readonly clock: SimpleSignal<number>;
  readonly label: string;
  readonly hint: string;
  /** 相对设计稿（44 pt 高）的放大倍数。 */
  readonly k?: number;
}

export interface FloatBar {
  readonly node: Node;
  show(): ThreadGenerator;
  toTranscribing(label: string, hint: string): ThreadGenerator;
  toRewriting(label: string, hint: string): ThreadGenerator;
  toInserted(label: string, hint: string): ThreadGenerator;
}

const BAR_X = [-6.3, 0, 6.3];
const BAR_BASE = [0.55, 1, 0.7];
const STAR: [number, number][] = [[0, -6], [1.6, -1.6], [6, 0], [1.6, 1.6], [0, 6], [-1.6, 1.6], [-6, 0], [-1.6, -1.6]];
const CHECK: [number, number][] = [[-5.5, 0.3], [-1.7, 4.1], [5.6, -3.5]];

export function createFloatBar({accent, clock, label, hint, k = 2}: FloatBarOptions): FloatBar {
  const labelFont = `600 ${13 * k}px ${FONT_SANS}`;
  const hintFont = `400 ${13 * k}px ${FONT_SANS}`;
  const textWidth = (l: string, h: string) => measureText(l, labelFont) + 10 * k + measureText(h, hintFont);
  const pillWidth = (l: string, h: string) => (5 + 34 + 10 + 16) * k + textWidth(l, h);

  const width = createSignal(pillWidth(label, hint));
  const border = colorSignal(() => new Color(read(accent)).alpha(0.55));
  const ballFill = colorSignal(() => read(accent));
  const arcColor = colorSignal(() => read(accent));
  const listening = createSignal(1); // 声波跟随音量的比例
  const converge = createSignal(0); // 签名动作：声波向中心收拢
  const barsOpacity = createSignal(1);
  const arcOpacity = createSignal(0);
  const arcSweep = createSignal(0); // 0…1 圆弧长度
  const spinning = createSignal(0);
  const starScale = createSignal(0.4);
  const starOpacity = createSignal(0);
  const checkEnd = createSignal(0);

  const root = createRef<Node>();
  const texts = createRef<Node>();
  const labelTxt = createRef<Txt>();
  const hintTxt = createRef<Txt>();

  const ballX = () => -width() / 2 + (5 + 17) * k;
  const textX = () => ballX() + (17 + 10) * k;
  const barHeight = (i: number) => () => {
    const a = voiceLevel(clock(), i);
    const live = Math.max(0.22, Math.min(1, (0.25 + 0.75 * a) * BAR_BASE[i] + 0.1));
    const shaped = 0.5 + (live - 0.5) * listening();
    return 16 * k * (shaped * (1 - converge()) + 0.16 * converge());
  };

  // 外层 node 由调用方定位；内层 root 只做出现动画的位移与缩放。
  const node = (
    <Node>
    <Node ref={root} opacity={0}>
      <Rect
        width={width} height={44 * k} radius={22 * k}
        fill={COLORS.barBg} stroke={border} lineWidth={1.2 * k}
        shadowColor={'rgba(0,0,0,0.5)'} shadowBlur={24 * k} shadowOffset={[0, 8 * k]}
      />
      <Node x={ballX} scale={k}>
        <Circle size={34} fill={ballFill} />
        <Node opacity={barsOpacity}>
          {BAR_X.map((x, i) => (
            <Rect
              x={() => x * (1 - converge())} width={3.4} height={() => barHeight(i)() / k}
              radius={1.7} fill={'#FFFFFF'}
            />
          ))}
        </Node>
        <Circle
          size={16} stroke={arcColor} lineWidth={2.6} lineCap={'round'} opacity={arcOpacity}
          startAngle={-90} endAngle={() => -90 + 359.9 * arcSweep()}
          rotation={() => spinning() * ((clock() * 300) % 360)}
        />
        <Line
          points={STAR} closed fill={'#FFFFFF'} scale={starScale} opacity={starOpacity}
        />
        <Line
          points={CHECK} stroke={'#FFFFFF'} lineWidth={2.6} lineCap={'round'} lineJoin={'round'} end={checkEnd}
        />
      </Node>
      <Node ref={texts} x={textX}>
        <Txt
          ref={labelTxt} text={label} offsetX={-1} fontFamily={FONT_SANS} fontWeight={600}
          fontSize={13 * k} fill={COLORS.fg}
        />
        <Txt
          ref={hintTxt} text={hint} offsetX={-1} fontFamily={FONT_SANS} fontWeight={400}
          fontSize={13 * k} fill={COLORS.fg} opacity={0.62}
          x={() => measureText(labelTxt().text(), labelFont) + 10 * k}
        />
      </Node>
    </Node>
    </Node>
  ) as Node;

  /** 状态切换：文字上移 4 pt 淡出，新文字从下方淡入；宽度同步弹簧过去。 */
  function* swapText(l: string, h: string): ThreadGenerator {
    yield* all(
      width(pillWidth(l, h), 0.3, easeOutBack),
      (function* () {
        yield* all(texts().opacity(0, 0.09), texts().y(-4 * k, 0.09));
        labelTxt().text(l);
        hintTxt().text(h);
        texts().y(4 * k);
        yield* all(texts().opacity(1, 0.14, easeOutCubic), texts().y(0, 0.14, easeOutCubic));
      })(),
    );
  }

  return {
    node,
    *show() {
      root().y(10 * k).scale(0.96);
      yield* all(root().opacity(1, 0.3), root().y(0, 0.3, easeOutCubic), root().scale(1, 0.3, easeOutBack));
    },
    *toTranscribing(l, h) {
      const soft = () => new Color(read(accent)).alpha(0.18);
      yield* all(
        converge(1, 0.2, easeInOutCubic),
        delay(0.14, barsOpacity(0, 0.12)),
        ballFill(soft, 0.18),
        swapText(l, h),
        delay(0.18, all(arcOpacity(1, 0.1), arcSweep(0.28, 0.24, easeOutCubic), spinning(1, 0))),
      );
    },
    *toRewriting(l, h) {
      yield* all(
        ballFill(() => read(accent), 0.18),
        arcColor('#FFFFFF', 0.18),
        starOpacity(1, 0.14),
        starScale(1, 0.22, easeOutBack),
        swapText(l, h),
      );
    },
    *toInserted(l, h) {
      yield* all(starOpacity(0, 0.14), starScale(0.4, 0.14), arcSweep(1, 0.2, easeOutCubic), swapText(l, h));
      spinning(0);
      yield* all(
        ballFill(COLORS.success, 0.18),
        border(new Color(COLORS.success).alpha(0.6), 0.18),
        arcOpacity(0, 0.12),
        checkEnd(1, 0.35, easeOutCubic),
      );
    },
  };
}

/** 主题段用：一直处于「正在听」的浮条，颜色跟随主题信号。 */
export function listeningBar(opts: FloatBarOptions): Node {
  const bar = createFloatBar({...opts});
  (bar.node.children()[0] as Node).opacity(1);
  return bar.node;
}
