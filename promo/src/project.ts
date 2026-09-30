/**
 * Motion Canvas 项目入口：五个场景按 timing.ts 的段落表首尾相接。
 * 编辑器预览（pnpm dev）会同步播放程序合成的配乐；成片音轨由 scripts/encode.ts 合成。
 * 需先运行 pnpm music 生成 music/out/soundtrack.wav。
 */
import {makeProject} from '@motion-canvas/core';
import './brand/fonts.ts';
import soundtrack from '../music/out/soundtrack.wav';
import intro from './scenes/intro?scene';
import pipeline from './scenes/pipeline?scene';
import features from './scenes/features?scene';
import themes from './scenes/themes?scene';
import outro from './scenes/outro?scene';

export default makeProject({
  scenes: [intro, pipeline, features, themes, outro],
  audio: soundtrack,
});
