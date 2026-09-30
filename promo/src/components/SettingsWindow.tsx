/**
 * 设置窗口（矢量重绘）：侧栏选中「外观」，内容区是主题色、外观模式、浮条预览、菜单栏动画四行，
 * 右侧大号应用图标。所有强调色都读 ThemeSignals，换主题时整窗 250 ms 渐变过去。
 */
import {Circle, Node, Rect, Txt} from '@motion-canvas/2d';
import {createSignal, type PossibleColor, type SimpleSignal} from '@motion-canvas/core';
import {COLORS, THEMES} from '../brand/colors.ts';
import {FONT_CJK, FONT_SANS} from '../brand/fonts.ts';
import {PIPELINE, THEMES_COPY} from '../copy.ts';
import {listeningBar} from './FloatBar.tsx';
import {MacWindow} from './MacWindow.tsx';
import {lerpColor} from './beat.ts';

export interface ThemeSignals {
  readonly accent: SimpleSignal<PossibleColor>;
  readonly soft: SimpleSignal<PossibleColor>;
  readonly iconTop: SimpleSignal<PossibleColor>;
  readonly iconBottom: SimpleSignal<PossibleColor>;
  /** 选中色环的横坐标（弹簧移动）。 */
  readonly ringX: SimpleSignal<number>;
  readonly name: SimpleSignal<string>;
}

export const WIN_W = 1300;
export const WIN_H = 720;
const SIDEBAR_W = 260;
const LEFT = -WIN_W / 2 + SIDEBAR_W + 50;
const ROW_X = LEFT + 250; // 控件起点
export const SWATCH_GAP = 72;
/** 大图标在窗口内容坐标中的位置与尺寸（主题段结尾它要飞出去当标志）。 */
export const ICON_POS = {x: 480, y: -20, size: 200};

export function swatchX(i: number): number {
  return ROW_X + 23 + i * SWATCH_GAP;
}

const label = (y: number, text: string) => (
  <Txt x={LEFT} y={y} offsetX={-1} text={text} fontFamily={FONT_CJK} fontWeight={500} fontSize={26} fill={COLORS.fg} />
);
const CONTROL_END = 310;
const divider = (y: number) => <Rect x={(LEFT + CONTROL_END) / 2} y={y} width={CONTROL_END - LEFT} height={1.5} fill={COLORS.line} />;

export function SettingsWindow({theme, clock}: {theme: ThemeSignals; clock: SimpleSignal<number>}): Node {
  const top = -(WIN_H - 52) / 2;
  const ink = COLORS.ink;
  const rowY = {theme: -150, mode: -50, bar: 60, menu: 170};
  const segW = 130;
  return (
    <MacWindow width={WIN_W} height={WIN_H} title={THEMES_COPY.windowTitle}>
      {/* 侧栏 */}
      <Rect x={-WIN_W / 2 + SIDEBAR_W / 2} width={SIDEBAR_W} height={WIN_H - 52} radius={[0, 0, 0, 20]} fill={COLORS.bgRaise} />
      <Rect x={-WIN_W / 2 + SIDEBAR_W / 2} y={top + 60 + THEMES_COPY.selectedIndex * 58} width={SIDEBAR_W - 32} height={48}
        radius={12} fill={theme.accent} />
      {THEMES_COPY.sidebar.map((item, i) => (
        <Txt x={-WIN_W / 2 + 40} y={top + 60 + i * 58} offsetX={-1} text={item} fontFamily={FONT_CJK} fontSize={24}
          fontWeight={i === THEMES_COPY.selectedIndex ? 700 : 400}
          fill={i === THEMES_COPY.selectedIndex ? ink : COLORS.muted} />
      ))}
      {/* 标题 */}
      <Txt x={LEFT} y={top + 58} offsetX={-1} text={THEMES_COPY.pageTitle} fontFamily={FONT_CJK} fontWeight={700} fontSize={40} fill={COLORS.fg} />
      {/* 主题色 */}
      {label(rowY.theme, THEMES_COPY.rowTheme)}
      {THEMES.map((t, i) => (
        <Circle x={swatchX(i)} y={rowY.theme} size={46} fill={t.accentDark} stroke={'rgba(255,255,255,0.12)'} lineWidth={1} />
      ))}
      <Circle x={theme.ringX} y={rowY.theme} size={62} stroke={COLORS.fg} lineWidth={3.5} />
      {divider(rowY.theme + 50)}
      {/* 外观模式：分段控件，选中「深色」 */}
      {label(rowY.mode, THEMES_COPY.rowAppearance)}
      <Rect x={ROW_X + segW * 1.5} y={rowY.mode} width={segW * 3} height={52} radius={14} fill={COLORS.bgRaise}
        stroke={COLORS.line} lineWidth={1.5} />
      <Rect x={ROW_X + segW * 2.5} y={rowY.mode} width={segW - 8} height={44} radius={11} fill={theme.accent} />
      {THEMES_COPY.appearanceOptions.map((o, i) => (
        <Txt x={ROW_X + segW * (i + 0.5)} y={rowY.mode} text={o} fontFamily={FONT_CJK} fontSize={22}
          fontWeight={i === 2 ? 700 : 400} fill={i === 2 ? ink : COLORS.muted} />
      ))}
      {divider(rowY.mode + 55)}
      {/* 浮条预览 */}
      {label(rowY.bar, THEMES_COPY.rowBar)}
      <Node x={ROW_X + 200} y={rowY.bar}>
        {listeningBar({accent: theme.accent, clock, label: PIPELINE.bar.listening[0], hint: PIPELINE.bar.listening[1], k: 1.5})}
      </Node>
      {divider(rowY.bar + 55)}
      {/* 菜单栏动画：开关打开 */}
      {label(rowY.menu, THEMES_COPY.rowMenu)}
      <Rect x={ROW_X + 40} y={rowY.menu} width={80} height={44} radius={22} fill={theme.accent} />
      <Circle x={ROW_X + 58} y={rowY.menu} size={36} fill={'#FFFFFF'} />
      {/* 预览：主题浅底卡片 + 名称（图标由场景单独绘制，便于结尾飞出） */}
      <Rect x={ICON_POS.x} y={ICON_POS.y + 30} width={270} height={400} radius={28} fill={theme.soft} />
      <Txt x={ICON_POS.x} y={ICON_POS.y + 170} text={theme.name} fontFamily={FONT_CJK} fontWeight={700} fontSize={28}
        fill={theme.accent} />
      <Txt x={LEFT} y={top + 640} offsetX={-1} text={THEMES.map(t => t.name).join(' · ')} fontFamily={FONT_SANS}
        fontSize={20} fill={COLORS.faint} />
    </MacWindow>
  ) as Node;
}

export function createThemeSignals(): ThemeSignals {
  const lerp = lerpColor;
  const t = THEMES[0];
  return {
    accent: createSignal<PossibleColor>(t.accentDark, lerp),
    soft: createSignal<PossibleColor>(t.accentSoftDark, lerp),
    iconTop: createSignal<PossibleColor>(t.iconTop, lerp),
    iconBottom: createSignal<PossibleColor>(t.iconBottom, lerp),
    ringX: createSignal(swatchX(0)),
    name: createSignal(`${t.name} · ${t.nameEn}`),
  };
}
