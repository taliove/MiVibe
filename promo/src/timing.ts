/**
 * 全片唯一的节拍来源：画面（Motion Canvas 场景）与配乐（music/）都从这里取时间。
 *
 * 120 BPM → 一拍 0.5 s，一小节（4/4）2 s；60 fps 下一拍正好 30 帧，
 * 所以每个场景切点都落在整数帧上，与音频采样对齐（卡点）。
 */

export const BPM = 120;
export const BEAT = 60 / BPM; // 秒
export const BEATS_PER_BAR = 4;
export const BAR = BEAT * BEATS_PER_BAR;
export const FPS = 60;
export const SAMPLE_RATE = 48000;

/** 拍数 → 秒。 */
export const beats = (n: number): number => n * BEAT;
/** 小节数 → 秒。 */
export const bars = (n: number): number => n * BAR;

/** 场景表：起点与长度都以拍计，顺序即成片顺序。 */
export interface Section {
  readonly id: SectionId;
  readonly startBeat: number;
  readonly lengthBeats: number;
}

export type SectionId = 'intro' | 'pipeline' | 'features' | 'themes' | 'outro';

const LENGTHS: ReadonlyArray<readonly [SectionId, number]> = [
  ['intro', 8], // 0–4 s：按住，说话
  ['pipeline', 20], // 4–14 s：声音 → 识别 → 纠正 → 改写 → 输入
  ['features', 32], // 14–30 s：功能快切（6 张卡 × 4 拍 + 8 拍总览）
  ['themes', 20], // 30–40 s：设置窗口换主题；最后 4 拍是冲击前的上升段
  ['outro', 12], // 40–46 s：冲击 + 标志展示，音乐淡出
];

export const SECTIONS: ReadonlyArray<Section> = LENGTHS.reduce<Section[]>(
  (acc, [id, lengthBeats]) => {
    const prev = acc[acc.length - 1];
    const startBeat = prev ? prev.startBeat + prev.lengthBeats : 0;
    return [...acc, {id, startBeat, lengthBeats}];
  },
  [],
);

export const TOTAL_BEATS = SECTIONS.reduce((sum, s) => sum + s.lengthBeats, 0);
export const DURATION = beats(TOTAL_BEATS);

export function section(id: SectionId): Section {
  const found = SECTIONS.find(s => s.id === id);
  if (!found) throw new Error(`unknown section: ${id}`);
  return found;
}

/** 功能快切段内部的节拍编排（场景与配乐共用）。 */
export const FEATURE_CARD_BEATS = 4;
export const FEATURE_CARD_COUNT = 6;

/** 主题段：每次换色所在的拍（相对主题段起点）。 */
export const THEME_SWITCH_BEATS: ReadonlyArray<number> = [4, 6, 8, 10, 12, 14];
/** 主题段内冲击前上升段起点（相对主题段起点）。 */
export const RISER_START_BEAT = 16;

/** 结尾：音乐从哪一拍开始淡出（相对全片），以及淡出长度。 */
export const FADE_START_BEAT = TOTAL_BEATS - 6;
export const FADE_BEATS = 6;
