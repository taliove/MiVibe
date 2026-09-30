/**
 * 字体：Inter（拉丁）+ Noto Sans SC（中文）+ JetBrains Mono（等宽），均为 SIL Open Font License 1.1，
 * 通过 @fontsource 包以 woff2 分片引入（见 README 的许可说明）。
 *
 * Canvas 绘字不会等待网络字体；渲染前必须先 document.fonts.load，
 * 按实际出现的文字把需要的 unicode-range 分片全部拉下来。
 */
import '@fontsource/inter/400.css';
import '@fontsource/inter/500.css';
import '@fontsource/inter/600.css';
import '@fontsource/inter/700.css';
import '@fontsource/noto-sans-sc/400.css';
import '@fontsource/noto-sans-sc/500.css';
import '@fontsource/noto-sans-sc/700.css';
import '@fontsource/jetbrains-mono/500.css';
import '@fontsource/jetbrains-mono/600.css';
import {ALL_COPY} from '../copy.ts';

export const FONT_SANS = 'Inter, "Noto Sans SC", sans-serif';
export const FONT_CJK = '"Noto Sans SC", Inter, sans-serif';
export const FONT_MONO = '"JetBrains Mono", "Noto Sans SC", monospace';

const FACES: ReadonlyArray<readonly [family: string, weight: number]> = [
  ['Inter', 400], ['Inter', 500], ['Inter', 600], ['Inter', 700],
  ['Noto Sans SC', 400], ['Noto Sans SC', 500], ['Noto Sans SC', 700],
  ['JetBrains Mono', 500], ['JetBrains Mono', 600],
];

export async function preloadFonts(): Promise<void> {
  const text = Array.from(new Set(ALL_COPY.join(''))).join('');
  await Promise.all(
    FACES.map(([family, weight]) => document.fonts.load(`${weight} 64px "${family}"`, text)),
  );
  await document.fonts.ready;
}
