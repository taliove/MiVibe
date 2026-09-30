import {defineConfig} from 'vite';
import motionCanvasPlugin from '@motion-canvas/vite-plugin';
import ffmpegPlugin from '@motion-canvas/ffmpeg';

// CJS 默认导出在 ESM 下可能被包一层 default，这里统一取出函数本身。
const unwrap = <T>(m: T): T => ((m as {default?: T}).default ?? m);
const motionCanvas = unwrap(motionCanvasPlugin);
const ffmpeg = unwrap(ffmpegPlugin);

// pnpm dev 打开 Motion Canvas 编辑器（可预览、拖动时间轴、同步播放配乐）；
// scripts/render.ts 复用同一个开发服务器，但打开的是无界面的 render.html。
export default defineConfig({
  plugins: [
    motionCanvas({project: './src/project.ts', output: './output/frames'}),
    ffmpeg(),
  ],
});
