/**
 * 场景 2（4–14 s，20 拍）：一句话走完整条链路，每个阶段落在拍点上。
 *   0 拍 正在听（声波）→ 4 拍 松手 · 签名动作 · 识别出原文
 *   8 拍 关键词纠正 mi vibe → MiVibe → 10 拍 改写 → 12 拍 输入框逐字写入 → 15 拍 ✓ 已输入
 */
import {Node, Rect, Txt, makeScene2D} from '@motion-canvas/2d';
import {
  Color, all, createRef, createSignal, easeInOutCubic, easeOutCubic, linear,
} from '@motion-canvas/core';
import {COLORS, TIDE} from '../brand/colors.ts';
import {FONT_CJK} from '../brand/fonts.ts';
import {PIPELINE} from '../copy.ts';
import {beats, section} from '../timing.ts';
import {Backdrop} from '../components/Backdrop.tsx';
import {createFloatBar} from '../components/FloatBar.tsx';
import {MacWindow} from '../components/MacWindow.tsx';
import {createStageChips} from '../components/StageChips.tsx';
import {Waveform} from '../components/Waveform.tsx';
import {at, colorSignal, makeClock, endScene} from '../components/beat.ts';
import {measureText} from '../components/measure.ts';

const LINE_Y = -100;
const LINE_SIZE = 64;
const FIELD_SIZE = 44;
const lineFont = `500 ${LINE_SIZE}px ${FONT_CJK}`;
const fieldFont = `500 ${FIELD_SIZE}px ${FONT_CJK}`;

// 原文拆成「前缀 / 待纠正词 / 后缀」三段，纠正时只替换中间一段。
const [PREFIX, SUFFIX] = PIPELINE.raw.split(PIPELINE.wrong);

export default makeScene2D(function* (view) {
  const {clock, run} = makeClock();
  yield run();
  const accent = TIDE.accentDark;
  // 测宽放在场景运行时：此时字体已加载，模块求值时还没有。
  const LEFT = -measureText(PIPELINE.corrected, lineFont) / 2;
  const MID_X = LEFT + measureText(PREFIX, lineFont);

  const waveAmp = createSignal(0);
  const collapse = createSignal(0);
  const waveOpacity = createSignal(1);
  const typed = createSignal(0); // 识别原文已出现的字数
  const fieldTyped = createSignal(0); // 输入框已写入的字数
  const fieldTyping = createSignal(0);
  const hlFill = colorSignal(new Color(COLORS.attention).alpha(0));
  const hlStroke = colorSignal(new Color(COLORS.attention).alpha(0));
  const midFill = colorSignal(COLORS.fg);

  const row = createRef<Node>();
  const midTxt = createRef<Txt>();
  const rewritten = createRef<Txt>();
  const win = createRef<Node>();

  const chips = createStageChips(PIPELINE.stages, -370);
  const bar = createFloatBar({
    accent, clock, label: PIPELINE.bar.listening[0], hint: PIPELINE.bar.listening[1], k: 2.3,
  });
  bar.node.y(405);

  const n = () => Math.round(typed());
  const midWidth = () => measureText(midTxt().text(), lineFont);
  const fieldText = () => PIPELINE.rewritten.slice(0, Math.round(fieldTyped()));
  const caretOn = () => (fieldTyping() > 0 || Math.floor(clock() * 2) % 2 === 0 ? 1 : 0);

  view.add(
    <Node>
      <Backdrop glowY={-120} />
      {chips.node}
      <Node opacity={waveOpacity}>
        <Waveform clock={clock} collapse={collapse} amp={waveAmp} color={accent} y={LINE_Y} />
      </Node>
      <Node ref={row} y={LINE_Y}>
        <Rect
          x={() => MID_X + midWidth() / 2} width={() => midWidth() + 22} height={LINE_SIZE * 1.3}
          radius={14} fill={hlFill} stroke={hlStroke} lineWidth={2.5}
        />
        <Txt x={LEFT} offsetX={-1} text={() => PREFIX.slice(0, n())}
          fontFamily={FONT_CJK} fontWeight={500} fontSize={LINE_SIZE} fill={COLORS.fg} />
        <Txt ref={midTxt} x={MID_X} offsetX={-1}
          text={() => PIPELINE.wrong.slice(0, Math.max(0, n() - PREFIX.length))}
          fontFamily={FONT_CJK} fontWeight={500} fontSize={LINE_SIZE} fill={midFill} />
        <Txt x={() => MID_X + midWidth()} offsetX={-1}
          text={() => SUFFIX.slice(0, Math.max(0, n() - PREFIX.length - PIPELINE.wrong.length))}
          fontFamily={FONT_CJK} fontWeight={500} fontSize={LINE_SIZE} fill={COLORS.fg} />
      </Node>
      <Txt ref={rewritten} y={LINE_Y + 40} opacity={0} text={PIPELINE.rewritten}
        fontFamily={FONT_CJK} fontWeight={500} fontSize={LINE_SIZE} fill={COLORS.fg} />
      <Node ref={win} y={175} opacity={0}>
        <MacWindow width={1180} height={210} title={PIPELINE.windowTitle}>
          <Rect width={1100} height={96} radius={16} fill={COLORS.bg}
            stroke={new Color(accent).alpha(0.55)} lineWidth={2} />
          <Txt x={-525} offsetX={-1} text={PIPELINE.fieldPlaceholder} fill={COLORS.faint}
            opacity={() => (fieldTyped() < 0.5 ? 1 : 0)}
            fontFamily={FONT_CJK} fontWeight={400} fontSize={FIELD_SIZE} />
          <Txt x={-525} offsetX={-1} text={fieldText} fill={COLORS.fg}
            fontFamily={FONT_CJK} fontWeight={500} fontSize={FIELD_SIZE} />
          <Rect x={() => -525 + measureText(fieldText(), fieldFont) + 5} width={3.5} height={54}
            radius={2} fill={accent} opacity={caretOn} />
        </MacWindow>
      </Node>
      {bar.node}
    </Node>,
  );

  // 0 拍：链路芯片依次出现，浮条「正在听」，声波起伏。
  win().y(205);
  yield all(chips.enter(), win().opacity(1, 0.4), win().y(175, 0.5, easeOutCubic), bar.show());
  yield chips.activate(0);
  yield waveAmp(1, 0.5, easeOutCubic);

  // 4 拍：松开语音键 → 签名动作；识别结果逐字浮现。
  yield at(4, function* () {
    yield* all(collapse(1, 0.2, easeInOutCubic), chips.activate(1), bar.toTranscribing(...PIPELINE.bar.transcribing));
    yield* waveOpacity(0, 0.15);
  });
  yield at(4.5, () => typed(PIPELINE.raw.length, beats(2.5), linear));

  // 8 拍：关键词纠正——先标出错词，下一拍替换成正确写法。
  yield at(8, function* () {
    yield* all(
      chips.activate(2),
      hlFill(new Color(COLORS.attention).alpha(0.16), 0.2),
      hlStroke(new Color(COLORS.attention).alpha(0.9), 0.2),
      midFill(COLORS.attention, 0.2),
    );
  });
  yield at(9, function* () {
    yield* midTxt().opacity(0, 0.1);
    midTxt().text(PIPELINE.fixed);
    yield* all(
      midTxt().opacity(1, 0.18),
      midFill(accent, 0.18),
      hlFill(new Color(accent).alpha(0.16), 0.25),
      hlStroke(new Color(accent).alpha(0.9), 0.25),
    );
  });

  // 10 拍：改写（可选）——浮条填满主题色，句子换成书面语。
  yield at(10, () => all(chips.activate(3), bar.toRewriting(...PIPELINE.bar.rewriting)));
  yield at(11, function* () {
    yield* all(
      row().opacity(0, 0.25), row().y(LINE_Y - 40, 0.3, easeInOutCubic),
      rewritten().opacity(1, 0.35), rewritten().y(LINE_Y, 0.4, easeOutCubic),
    );
  });

  // 12 拍：写入目标输入框（光标跟随），15 拍 ✓ 已输入。
  yield at(12, function* () {
    fieldTyping(1);
    yield* all(chips.activate(4), rewritten().opacity(0.4, 0.3), fieldTyped(PIPELINE.rewritten.length, beats(2.5), linear));
    fieldTyping(0);
  });
  yield at(15, () => bar.toInserted(...PIPELINE.bar.inserted));

  yield* endScene(section('pipeline').lengthBeats);
});
