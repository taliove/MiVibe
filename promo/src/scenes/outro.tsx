/**
 * 场景 5（40–46 s，12 拍）：第 0 拍冲击——闪白、冲击波、图标回弹，标志的三根声波像电平表一样跳起；
 * 随后逐拍推出 MiVibe 字标、「开源 · macOS」与仓库地址，停留，最后两拍淡到黑（配乐同步淡出）。
 */
import {Circle, Node, Rect, Txt, makeScene2D} from '@motion-canvas/2d';
import {
  all, createRef, createSignal, delay, easeOutBack, easeOutCubic, easeOutExpo, linear,
  type ThreadGenerator,
} from '@motion-canvas/core';
import {COLORS, TIDE} from '../brand/colors.ts';
import {FONT_CJK, FONT_MONO, FONT_SANS} from '../brand/fonts.ts';
import {OUTRO} from '../copy.ts';
import {BEAT, beats, section} from '../timing.ts';
import {Backdrop} from '../components/Backdrop.tsx';
import {AppIcon} from '../components/Brand.tsx';
import {at, makeClock, voiceLevel, endScene} from '../components/beat.ts';
import {measureText} from '../components/measure.ts';
import {LOGO_SIZE, LOGO_Y} from './logo.ts';

const LENGTH = section('outro').lengthBeats;

/** 遮罩推入：文字从遮罩下方升起。 */
function* riseIn(txt: Txt, from: number, dur = 0.55): ThreadGenerator {
  txt.y(from);
  yield* all(txt.y(0, dur, easeOutCubic), txt.opacity(1, dur * 0.6));
}

export default makeScene2D(function* (view) {
  const {clock, run} = makeClock();
  yield run();
  const accent = TIDE.accentDark;
  const glow = createSignal(1.8);
  const meter = createSignal(1); // 冲击后电平跳动幅度，逐渐衰减到呼吸
  const flash = createSignal(0);
  const fade = createSignal(0);
  const icon = createRef<Node>();
  const rings = createRef<Node>();
  const word = createRef<Txt>();
  const cn = createRef<Txt>();
  const en = createRef<Txt>();
  const url = createRef<Txt>();
  const underline = createSignal(0);
  const urlFont = `500 30px ${FONT_MONO}`;
  const urlW = measureText(OUTRO.url, urlFont);

  const barScales = [0, 1, 2].map(i => () => {
    const live = voiceLevel(clock() * 1.8, i * 1.7);
    return 1 + meter() * (live - 0.4) * 1.1 + 0.03 * Math.sin(clock() * Math.PI + i);
  });
  const mask = (y: number, h: number, child: Node) => (
    <Rect y={y} width={1600} height={h} clip>{child}</Rect>
  );

  view.add(
    <Node>
      <Backdrop glow={glow} glowY={LOGO_Y + 60} />
      <Node ref={rings} y={LOGO_Y} />
      <Node ref={icon} y={LOGO_Y}>
        <AppIcon size={LOGO_SIZE} top={TIDE.iconTop} bottom={TIDE.iconBottom} barScales={barScales} />
      </Node>
      {mask(95, 190, (
        <Txt ref={word} text={OUTRO.name} fontFamily={FONT_SANS} fontWeight={700} fontSize={150}
          letterSpacing={-3} fill={COLORS.fg} opacity={0} />
      ) as Node)}
      {mask(222, 64, (
        <Txt ref={cn} text={OUTRO.cn} fontFamily={FONT_CJK} fontWeight={500} fontSize={44} fill={COLORS.fg} opacity={0} />
      ) as Node)}
      {mask(272, 40, (
        <Txt ref={en} text={OUTRO.en} fontFamily={FONT_SANS} fontWeight={500} fontSize={26} letterSpacing={1}
          fill={COLORS.muted} opacity={0} />
      ) as Node)}
      <Node y={350}>
        <Txt ref={url} text={OUTRO.url} fontFamily={FONT_MONO} fontWeight={500} fontSize={30} fill={accent} opacity={0} />
        <Rect y={28} width={() => urlW * underline()} height={2.5} radius={1.25} fill={accent} opacity={0.7} />
      </Node>
      <Rect width={1920} height={1080} fill={'#FFFFFF'} opacity={flash} />
      <Rect width={1920} height={1080} fill={COLORS.bg} opacity={fade} />
    </Node>,
  );

  function* shockwave(color: string, delaySec: number, width: number): ThreadGenerator {
    const ring = createRef<Circle>();
    rings().add(<Circle ref={ring} size={LOGO_SIZE} stroke={color} lineWidth={width} opacity={0} />);
    yield* delay(delaySec, all(
      ring().opacity(0.9, 0.02).to(0, 0.9, linear),
      ring().size(1900, 0.95, easeOutExpo),
      ring().lineWidth(0.5, 0.95),
    ));
    ring().remove();
  }

  // 第 0 拍：冲击。
  flash(0.55);
  icon().scale(1.16);
  yield flash(0, 0.3, easeOutCubic);
  yield icon().scale(1, 0.6, easeOutBack);
  yield shockwave(accent, 0, 10);
  yield shockwave('#FFFFFF', 0.08, 4);
  yield glow(3, 0.05).to(1.2, beats(4), easeOutCubic);
  yield meter(0.06, beats(5), easeOutCubic);

  // 逐拍推出文字。
  yield at(1, () => riseIn(word(), 190));
  yield at(2, () => all(riseIn(cn(), 64), delay(0.1, riseIn(en(), 40))));
  yield at(3, () => all(url().opacity(1, 0.3), underline(1, 0.5, easeOutCubic)));

  // 最后两拍淡到黑。
  yield at(LENGTH - 2, () => fade(1, BEAT * 2, linear));
  yield* endScene(LENGTH);
});
