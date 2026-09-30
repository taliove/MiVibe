/**
 * 品牌色板：逐字取自 MiVibe 的 Sources/MiVibeCore/Core/Theme.swift。
 * 宣传片是深色画面，所以界面元素用各主题的深色侧（accentDark / accentSoftDark），
 * 应用图标用 iconTop → iconBottom 渐变。
 */

export interface ThemePalette {
  readonly id: ThemeId;
  readonly name: string; // 中文名（设置界面展示）
  readonly nameEn: string;
  readonly accent: string;
  readonly accentStrong: string;
  readonly accentSoft: string;
  readonly accentDark: string;
  readonly accentSoftDark: string;
  readonly iconTop: string;
  readonly iconBottom: string;
}

export type ThemeId = 'tide' | 'indigo' | 'coral' | 'orchid' | 'rose' | 'graphite';

export const THEMES: ReadonlyArray<ThemePalette> = [
  {
    id: 'tide', name: '潮汐青', nameEn: 'Tide',
    accent: '#0C98A8', accentStrong: '#08717F', accentSoft: '#D7F1F2',
    accentDark: '#22B8C6', accentSoftDark: '#0F3439',
    iconTop: '#16B4C2', iconBottom: '#086978',
  },
  {
    id: 'indigo', name: '靛蓝', nameEn: 'Indigo',
    accent: '#4F5BD5', accentStrong: '#3A44B0', accentSoft: '#E3E5FB',
    accentDark: '#8591F5', accentSoftDark: '#1E2350',
    iconTop: '#6272F0', iconBottom: '#3B3FB8',
  },
  {
    id: 'coral', name: '珊瑚', nameEn: 'Coral',
    accent: '#E0503A', accentStrong: '#B83A27', accentSoft: '#FBE3DE',
    accentDark: '#FF7A62', accentSoftDark: '#43201A',
    iconTop: '#FF7157', iconBottom: '#C9362A',
  },
  {
    id: 'orchid', name: '兰紫', nameEn: 'Orchid',
    accent: '#8A4FD6', accentStrong: '#6C38B3', accentSoft: '#EEE3FB',
    accentDark: '#B48AF5', accentSoftDark: '#2E1D4A',
    iconTop: '#A56BF0', iconBottom: '#6A33B8',
  },
  {
    id: 'rose', name: '玫瑰', nameEn: 'Rose',
    accent: '#D2457A', accentStrong: '#A93360', accentSoft: '#FADFE9',
    accentDark: '#F27AA6', accentSoftDark: '#45192B',
    iconTop: '#EC5F93', iconBottom: '#B02F63',
  },
  {
    id: 'graphite', name: '石墨', nameEn: 'Graphite',
    accent: '#2E3A40', accentStrong: '#2E3A40', accentSoft: '#E1E6E8',
    accentDark: '#D5DEE1', accentSoftDark: '#222C31',
    iconTop: '#46545B', iconBottom: '#1B2327',
  },
];

export const TIDE = THEMES[0];

/** 画面通用色（深色外观，取自 design-system / motion 草案的深色令牌）。 */
export const COLORS = {
  bg: '#060B0C',
  bgRaise: '#0C1215',
  surface: '#121B1F',
  surfaceHi: '#18242A',
  line: '#23333A',
  fg: '#E4ECEE',
  muted: '#93A4A9',
  faint: '#5E7075',
  ink: '#13201F', // 深色填充面上的文字
  barBg: 'rgba(30,40,44,0.92)',
  success: '#3CC97D',
  attention: '#F0A43A',
  error: '#FF6B5C',
  note: '#93A5A9',
} as const;

/** 16 进制色 + 透明度 → rgba 字符串。 */
export function alpha(hex: string, a: number): string {
  const n = parseInt(hex.slice(1), 16);
  const r = (n >> 16) & 0xff;
  const g = (n >> 8) & 0xff;
  const b = n & 0xff;
  return `rgba(${r},${g},${b},${a})`;
}
