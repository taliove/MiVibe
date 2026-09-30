/**
 * 片中所有文字集中在这里：一处改文案，字体预加载（brand/fonts.ts）也自动覆盖到。
 * 大标题中文 + 小字英文。
 */
import {THEMES} from './brand/colors.ts';

export const INTRO = {
  headline: '按住，说话。',
  sub: 'Hold. Speak.',
  keyHint: '语音键',
} as const;

export const PIPELINE = {
  stages: [
    {cn: '声音', en: 'Voice'},
    {cn: '识别', en: 'Recognize'},
    {cn: '关键词纠正', en: 'Correct'},
    {cn: '改写', en: 'Rewrite', tag: '可选'},
    {cn: '输入', en: 'Type'},
  ],
  raw: '明天下午三点和 mi vibe 团队开会',
  wrong: 'mi vibe',
  fixed: 'MiVibe',
  corrected: '明天下午三点和 MiVibe 团队开会',
  rewritten: '明天 15:00 与 MiVibe 团队开会。',
  fieldPlaceholder: '写点什么…',
  windowTitle: '备忘录',
  bar: {
    listening: ['正在听', '松开语音键结束'],
    transcribing: ['正在转写', '可以说下一句'],
    rewriting: ['正在改写', '整理成正式语气'],
    inserted: ['已输入', '文字已写入目标输入框'],
  },
} as const;

export interface FeatureCopy {
  readonly cn: string;
  readonly en: string;
  readonly tag: string;
}

export const FEATURES: ReadonlyArray<FeatureCopy> = [
  {cn: '本地识别，完全离线', en: 'Fully offline, on-device recognition', tag: 'whisper.cpp'},
  {cn: '豆包云端识别', en: 'Doubao cloud speech recognition', tag: 'Doubao ASR'},
  {cn: '按键映射', en: 'Map remote keys to any shortcut', tag: 'Shortcuts'},
  {cn: '失败可恢复', en: 'Nothing is lost — recoverable queue', tag: 'Queue'},
  {cn: '输入 ≠ 发送', en: 'Typing never hits send', tag: 'Safe by design'},
  {cn: '六套主题', en: 'Six themes', tag: 'Themes'},
];

export const FEATURE_DETAIL = {
  offline: ['无网络', 'whisper.cpp · Metal'],
  cloud: ['流式识别', '豆包', 'Doubao · streaming'],
  keys: [
    ['确认', '⌘ ↩'],
    ['返回', '⌘ Z'],
    ['菜单', '切换模式'],
  ],
  queue: {
    title: 'MiVibe · 待处理',
    items: ['第一段口述', '第二段口述'],
    pending: '需处理',
    done: '已输入',
    action: '输入到这里',
    footer: 'Resume · Retry · Discard',
  },
  send: {text: '这段话先不发', button: '发送', hint: '发送是独立按键', key: 'return ↩'},
} as const;

export const RECAP = {
  headline: '一个遥控器，全部搞定。',
  sub: 'One remote. Everything in reach.',
} as const;

export const THEMES_COPY = {
  headline: '六套主题',
  sub: 'Six themes, one tap.',
  sidebar: ['识别', '改写', '按键映射', '遥控器', '外观', '关于'],
  selectedIndex: 4,
  pageTitle: '外观',
  rowTheme: '主题色',
  rowAppearance: '外观模式',
  appearanceOptions: ['跟随系统', '浅色', '深色'],
  rowBar: '浮条预览',
  rowMenu: '菜单栏动画',
  windowTitle: 'MiVibe 设置',
} as const;

export const OUTRO = {
  name: 'MiVibe',
  cn: '开源 · macOS',
  en: 'Open source · macOS',
  url: 'github.com/taliove/MiVibe',
} as const;

/** 所有会上屏的字符串（字体预加载用）。 */
export const ALL_COPY: ReadonlyArray<string> = [
  ...Object.values(INTRO),
  ...PIPELINE.stages.flatMap(s => [s.cn, s.en, 'tag' in s ? s.tag : '']),
  PIPELINE.raw, PIPELINE.corrected, PIPELINE.rewritten, PIPELINE.fieldPlaceholder, PIPELINE.windowTitle,
  ...Object.values(PIPELINE.bar).flat(),
  ...FEATURES.flatMap(f => [f.cn, f.en, f.tag]),
  ...FEATURE_DETAIL.offline, ...FEATURE_DETAIL.cloud, ...FEATURE_DETAIL.keys.flat(),
  ...Object.values(FEATURE_DETAIL.queue).flat(),
  ...Object.values(FEATURE_DETAIL.send),
  ...Object.values(RECAP),
  THEMES_COPY.headline, THEMES_COPY.sub, ...THEMES_COPY.sidebar, THEMES_COPY.pageTitle,
  THEMES_COPY.rowTheme, THEMES_COPY.rowAppearance, ...THEMES_COPY.appearanceOptions,
  THEMES_COPY.rowBar, THEMES_COPY.rowMenu, THEMES_COPY.windowTitle,
  ...THEMES.flatMap(t => [t.name, t.nameEn]),
  ...Object.values(OUTRO),
  '0123456789/·—≠→',
];
