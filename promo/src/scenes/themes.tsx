/**
 * 场景 4（30–40 s，20 拍）：设置窗口里的主题色随拍点轮换六套色板（图标 + 强调色整窗换色），
 * 第 14 拍回到潮汐青；第 16 拍起进入冲击前的上升段——窗口退场，应用图标飞到画面中央，
 * 声波开始蓄力跳动，第 20 拍硬切到结尾的冲击。
 */
import {Node, Txt, makeScene2D} from '@motion-canvas/2d';
import {
  all, createRef, createSignal, easeInCubic, easeInOutCubic, easeOutBack, easeOutCubic,
} from '@motion-canvas/core';
import {THEMES} from '../brand/colors.ts';
import {FONT_CJK} from '../brand/fonts.ts';
import {THEMES_COPY} from '../copy.ts';
import {RISER_START_BEAT, THEME_SWITCH_BEATS, beats, section} from '../timing.ts';
import {Backdrop} from '../components/Backdrop.tsx';
import {AppIcon} from '../components/Brand.tsx';
import {createCaption} from '../components/Caption.tsx';
import {ICON_POS, SettingsWindow, createThemeSignals, swatchX} from '../components/SettingsWindow.tsx';
import {at, makeClock, voiceLevel, endScene} from '../components/beat.ts';
import {LOGO_SIZE, LOGO_Y} from './logo.ts';

const WIN_Y = 70;
const TITLE_H = 52;

// 轮换顺序：靛蓝 → 珊瑚 → 兰紫 → 玫瑰 → 石墨 → 回到潮汐青。
const SEQUENCE = [1, 2, 3, 4, 5, 0];

export default makeScene2D(function* (view) {
  const {clock, run} = makeClock();
  yield run();
  const theme = createThemeSignals();
  const glow = createSignal(1);
  const charge = createSignal(0); // 上升段声波蓄力幅度
  const win = createRef<Node>();
  const chrome = createRef<Node>();
  const hero = createRef<Node>();
  const caption = createCaption({
    cn: THEMES_COPY.headline, en: THEMES_COPY.sub, x: -650, y: -415, size: 72, align: -1,
  });
  const barScales = [0, 1, 2].map(i => () => 1 + charge() * (voiceLevel(clock() * 1.6, i) - 0.35) * 0.9);

  view.add(
    <Node>
      <Backdrop accent={theme.accent} glow={glow} glowY={0} />
      <Node ref={chrome}>
        {caption.node}
        <Txt x={650} y={-430} offsetX={1} text={theme.name} fontFamily={FONT_CJK} fontWeight={700}
          fontSize={40} fill={theme.accent} />
      </Node>
      <Node ref={win} y={WIN_Y + 40} opacity={0} scale={0.96}>
        <SettingsWindow theme={theme} clock={clock} />
      </Node>
      <Node ref={hero} x={ICON_POS.x} y={WIN_Y + TITLE_H / 2 + ICON_POS.y + 40} opacity={0} scale={0.96}>
        <AppIcon size={ICON_POS.size} top={theme.iconTop} bottom={theme.iconBottom} barScales={barScales} />
      </Node>
    </Node>,
  );

  const heroY = WIN_Y + TITLE_H / 2 + ICON_POS.y;
  yield all(
    win().opacity(1, 0.35), win().y(WIN_Y, 0.5, easeOutCubic), win().scale(1, 0.5, easeOutCubic),
    hero().opacity(1, 0.35), hero().y(heroY, 0.5, easeOutCubic), hero().scale(1, 0.5, easeOutCubic),
  );
  yield at(0.5, () => caption.reveal(0.15));

  // 每个换色点：整窗 250 ms 渐变（motion-v1 的 theme 令牌），选中环弹簧移动，图标轻弹一下。
  for (let k = 0; k < THEME_SWITCH_BEATS.length; k++) {
    const index = SEQUENCE[k];
    const t = THEMES[index];
    yield at(THEME_SWITCH_BEATS[k], function* () {
      theme.name(`${t.name} · ${t.nameEn}`);
      yield* all(
        theme.accent(t.accentDark, 0.25, easeInOutCubic),
        theme.soft(t.accentSoftDark, 0.25, easeInOutCubic),
        theme.iconTop(t.iconTop, 0.25, easeInOutCubic),
        theme.iconBottom(t.iconBottom, 0.25, easeInOutCubic),
        theme.ringX(swatchX(index), 0.3, easeOutBack),
        hero().scale(1.06, 0.08).to(1, 0.25, easeOutCubic),
      );
    });
  }

  // 上升段：窗口退场，图标飞到中央并放大，声波蓄力，辉光增强。
  const riseDur = beats(20 - RISER_START_BEAT - 0.5);
  yield at(RISER_START_BEAT, () =>
    all(
      win().opacity(0, beats(2), easeInCubic), win().scale(0.92, beats(2.5), easeInCubic),
      chrome().opacity(0, beats(2), easeInCubic),
      hero().x(0, riseDur, easeInOutCubic), hero().y(LOGO_Y, riseDur, easeInOutCubic),
      hero().scale(LOGO_SIZE / ICON_POS.size, riseDur, easeInOutCubic),
      charge(1, beats(4), easeInCubic),
      glow(1.8, beats(4), easeInCubic),
    ),
  );

  yield* endScene(section('themes').lengthBeats);
});
