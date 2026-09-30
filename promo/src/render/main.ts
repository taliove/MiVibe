/**
 * 无界面渲染入口（render.html）：由 scripts/render.ts 用无头 Chrome 打开。
 *
 * 不经过 Motion Canvas 编辑器 UI，直接用核心库的 Renderer 驱动项目，
 * 帧交给官方 @motion-canvas/ffmpeg 导出器（经 Vite HMR 通道送到服务端 ffmpeg）。
 * 渲染前先等字体就绪，避免 CJK 字形在首帧回退成系统字体。
 */
import {Renderer, RendererResult, Vector2} from '@motion-canvas/core';
import project from '../project.ts?project';
import {preloadFonts} from '../brand/fonts.ts';
import {DURATION, FPS} from '../timing.ts';
import {COLORS} from '../brand/colors.ts';

declare global {
  interface Window {
    __renderResult?: 'success' | 'error' | 'aborted';
    __renderProgress?: number;
  }
}

const status = document.getElementById('status')!;
const log = (msg: string) => {
  status.textContent = msg;
  console.log(msg);
};

async function main(): Promise<void> {
  log('loading fonts…');
  await preloadFonts();

  const params = new URLSearchParams(location.search);
  const from = Number(params.get('from') ?? 0);
  const to = Number(params.get('to') ?? DURATION);

  // 项目日志（场景报错等）转到控制台，让 scripts/render.ts 能看到。
  project.logger.onLogged.subscribe(entry => {
    if (entry.level === 'error' || entry.level === 'warn') {
      console.error(`[motion-canvas ${entry.level}] ${entry.message}\n${entry.stack ?? ''}`);
    }
  });

  const renderer = new Renderer(project);
  renderer.onFrameChanged.subscribe(frame => {
    window.__renderProgress = frame;
    if (frame % 60 === 0) log(`frame ${frame} / ${Math.round(to * FPS)}`);
  });

  const result = await new Promise<RendererResult>(resolve => {
    renderer.onFinished.subscribe(resolve);
    void renderer.render({
      name: 'video',
      range: [from, to],
      fps: FPS,
      size: new Vector2(1920, 1080),
      resolutionScale: 1,
      colorSpace: 'srgb',
      background: COLORS.bg,
      exporter: {
        name: '@motion-canvas/ffmpeg',
        options: {fastStart: true, includeAudio: false},
      },
    });
  });

  window.__renderResult =
    result === RendererResult.Success ? 'success' : result === RendererResult.Aborted ? 'aborted' : 'error';
  log(`done: ${window.__renderResult}`);
}

main().catch(err => {
  console.error(err);
  window.__renderResult = 'error';
});
