/**
 * 场景 3（14–30 s，32 拍）：六张功能卡片，每张 4 拍，切点落在每小节第一拍；
 * 最后 8 拍是六宫格总览「一个遥控器，全部搞定。」。
 */
import {Node, Rect, Txt, makeScene2D} from '@motion-canvas/2d';
import {
  Color, all, createRef, createSignal, easeOutBack, easeOutCubic, sequence,
} from '@motion-canvas/core';
import {COLORS, TIDE} from '../brand/colors.ts';
import {FONT_CJK, FONT_MONO, FONT_SANS} from '../brand/fonts.ts';
import {FEATURES, RECAP} from '../copy.ts';
import {FEATURE_CARD_BEATS, FEATURE_CARD_COUNT, section} from '../timing.ts';
import {Backdrop} from '../components/Backdrop.tsx';
import {createCaption} from '../components/Caption.tsx';
import {ProgressBar, createFeatureCard} from '../components/features/FeatureCard.tsx';
import {cloudIllustration, keysIllustration, offlineIllustration, type Illustration} from '../components/features/illustrationsA.tsx';
import {queueIllustration, sendIllustration, themesIllustration} from '../components/features/illustrationsB.tsx';
import {at, endScene} from '../components/beat.ts';

const ILLUSTRATIONS: ReadonlyArray<() => Illustration> = [
  offlineIllustration, cloudIllustration, keysIllustration,
  queueIllustration, sendIllustration, themesIllustration,
];

const RECAP_START = FEATURE_CARD_BEATS * FEATURE_CARD_COUNT;

export default makeScene2D(function* (view) {
  const current = createSignal(0);
  const progress = createRef<Node>();
  const cardsLayer = createRef<Node>();
  view.add(
    <Node>
      <Backdrop glowY={0} />
      <Node ref={cardsLayer} y={-20} />
      <Node ref={progress}>
        <ProgressBar total={FEATURE_CARD_COUNT} current={current} />
      </Node>
    </Node>,
  );

  const cards = FEATURES.map((copy, i) => {
    const illo = ILLUSTRATIONS[i]();
    const card = createFeatureCard(i, FEATURES.length, copy, illo.node);
    return {card, illo};
  });

  // 每张卡片在自己的第一拍硬切上屏（与底鼓重拍对齐），随后播放插画。
  for (let i = 0; i < cards.length; i++) {
    const {card, illo} = cards[i];
    yield at(i * FEATURE_CARD_BEATS, function* () {
      cardsLayer().removeChildren();
      cardsLayer().add(card.node);
      current(i);
      yield* all(card.enter(), illo.play());
    });
  }

  // 总览：标题 + 六宫格依次弹出（每半拍一格）。
  yield at(RECAP_START, function* () {
    cardsLayer().removeChildren();
    yield* progress().opacity(0, 0.15);
  });
  const caption = createCaption({cn: RECAP.headline, en: RECAP.sub, y: -330, size: 84});
  const tiles = FEATURES.map(() => createRef<Node>());
  const TILE_W = 520;
  const TILE_H = 230;
  view.add(caption.node);
  view.add(
    <Node y={110}>
      {FEATURES.map((f, i) => {
        const col = i % 3;
        const rowI = Math.floor(i / 3);
        return (
          <Node ref={tiles[i]} x={(col - 1) * (TILE_W + 36)} y={(rowI - 0.5) * (TILE_H + 36)} scale={0} opacity={0}>
            <Rect width={TILE_W} height={TILE_H} radius={28} fill={new Color(COLORS.surface).alpha(0.85)}
              stroke={COLORS.line} lineWidth={2} />
            <Rect x={-TILE_W / 2 + 48} y={-TILE_H / 2 + 44} width={40} height={6} radius={3} fill={TIDE.accentDark} />
            <Txt x={TILE_W / 2 - 36} y={-TILE_H / 2 + 46} offsetX={1} text={`0${i + 1}`} fontFamily={FONT_MONO}
              fontSize={22} fill={COLORS.faint} />
            <Txt x={-TILE_W / 2 + 28} y={4} offsetX={-1} text={f.cn} fontFamily={FONT_CJK} fontWeight={700}
              fontSize={f.cn.length > 6 ? 46 : 52} fill={COLORS.fg} />
            <Txt x={-TILE_W / 2 + 28} y={66} offsetX={-1} text={f.en} fontFamily={FONT_SANS} fontWeight={500}
              fontSize={f.en.length > 30 ? 19 : 21} fill={COLORS.muted} />
          </Node>
        );
      })}
    </Node>,
  );
  yield at(RECAP_START, () => caption.reveal(0.15));
  yield at(RECAP_START + 1, () =>
    sequence(0.25, ...tiles.map(t => all(t().scale(1, 0.45, easeOutBack), t().opacity(1, 0.2, easeOutCubic)))),
  );

  yield* endScene(section('features').lengthBeats);
});
