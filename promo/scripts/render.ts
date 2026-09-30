/**
 * 画面渲染：启动 Vite 开发服务器（Motion Canvas 插件 + 官方 ffmpeg 导出插件），
 * 用本机 Chrome 无头打开 render.html，由核心库 Renderer 逐帧导出到
 * output/frames/video.mp4（无音轨；音轨由 scripts/encode.ts 合成）。
 *
 * 用法：node scripts/render.ts [--from 秒] [--to 秒]
 * 环境变量 CHROME_PATH 可指定浏览器可执行文件；默认用 puppeteer 的 chrome 通道查找。
 */
import {createServer} from 'vite';
import puppeteer from 'puppeteer-core';
import {parseArgs} from 'node:util';
import {DURATION, FPS} from '../src/timing.ts';

const {values} = parseArgs({
  options: {
    from: {type: 'string', default: '0'},
    to: {type: 'string', default: String(DURATION)},
  },
});

const POLL_MS = 1000;
const TIMEOUT_MS = 30 * 60 * 1000;

async function launchBrowser() {
  const common = {
    headless: true,
    protocolTimeout: TIMEOUT_MS,
    args: [
      '--disable-background-timer-throttling',
      '--disable-renderer-backgrounding',
      '--disable-backgrounding-occluded-windows',
      '--force-color-profile=srgb',
      '--window-size=1920,1080',
    ],
  };
  const executablePath = process.env.CHROME_PATH;
  return executablePath
    ? puppeteer.launch({...common, executablePath})
    : puppeteer.launch({...common, channel: 'chrome'});
}

async function main(): Promise<void> {
  const server = await createServer({server: {port: 9321, strictPort: false}, logLevel: 'warn'});
  await server.listen();
  const base = server.resolvedUrls?.local[0];
  if (!base) throw new Error('vite dev server did not report a local URL');

  const browser = await launchBrowser();
  const started = Date.now();
  try {
    const page = await browser.newPage();
    await page.setViewport({width: 1920, height: 1080});
    page.on('console', msg => {
      const text = msg.text();
      if (msg.type() === 'error' || msg.type() === 'warn' || text.startsWith('done')) console.log(`[page] ${text}`);
    });
    page.on('pageerror', err => console.error('[page error]', err));

    await page.goto(`${base}render.html?from=${values.from}&to=${values.to}`);
    const total = Math.round((Number(values.to) - Number(values.from)) * FPS);
    let result: string | undefined;
    while (!result) {
      if (Date.now() - started > TIMEOUT_MS) throw new Error('render timed out');
      await new Promise(r => setTimeout(r, POLL_MS));
      const state = await page.evaluate(() => ({
        result: window.__renderResult,
        frame: window.__renderProgress ?? 0,
      }));
      result = state.result;
      process.stdout.write(`\rframe ${state.frame} / ${total}   `);
    }
    process.stdout.write('\n');
    if (result !== 'success') throw new Error(`render finished with: ${result}`);
    console.log(`rendered in ${((Date.now() - started) / 1000).toFixed(1)} s → output/frames/video.mp4`);
  } finally {
    await browser.close();
    await server.close();
  }
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
