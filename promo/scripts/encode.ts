/**
 * 成片封装：把 Motion Canvas 导出的无声 H.264（output/frames/video.mp4）与配乐合成
 * output/mivibe-promo.mp4（视频流直接复制、音轨 AAC 192k、faststart），
 * 再从流程段截 8 s 做首尾交叉淡化的循环 WebP（output/mivibe-loop.webp，给 README 顶部用）。
 *
 * 依赖系统 PATH 上的 ffmpeg；ffmpeg 不带 libwebp 时改用 img2webp（brew install webp）。
 * 用法：node scripts/encode.ts
 */
import {execFileSync} from 'node:child_process';
import {existsSync, mkdtempSync, readdirSync, rmSync, statSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {DURATION, FPS, beats, section} from '../src/timing.ts';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const FRAMES = join(ROOT, 'output', 'frames', 'video.mp4');
const MUSIC = join(ROOT, 'music', 'out', 'soundtrack.wav');
const VIDEO = join(ROOT, 'output', 'mivibe-promo.mp4');
const LOOP = join(ROOT, 'output', 'mivibe-loop.webp');

/**
 * 循环片段：流程段第 1.5 拍（芯片已就位、正在听）起 8.5 s，覆盖识别 → 纠正 → 改写 → 输入 → ✓；
 * 末尾 0.5 s 与开头交叉淡化，得到 8 s 近似无缝的循环。
 */
const LOOP_START = beats(section('pipeline').startBeat + 1.5);
const LOOP_LEN = 8;
const LOOP_XFADE = 0.5;
const LOOP_WIDTH = 1280;
const LOOP_FPS = 24;
const LOOP_QUALITY = 72;

function ffmpeg(args: string[]): void {
  execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...args], {stdio: 'inherit'});
}

function requireFile(path: string, hint: string): void {
  if (!existsSync(path)) throw new Error(`missing ${path} — run \`${hint}\` first`);
}

const mb = (path: string) => (statSync(path).size / 1024 / 1024).toFixed(2);

function muxVideo(): void {
  ffmpeg([
    '-i', FRAMES, '-i', MUSIC,
    '-map', '0:v:0', '-map', '1:a:0',
    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k',
    '-frames:v', String(Math.round(DURATION * FPS)), '-t', DURATION.toFixed(3),
    '-movflags', '+faststart',
    VIDEO,
  ]);
  console.log(`video → output/mivibe-promo.mp4 (${mb(VIDEO)} MB)`);
}

/** 截取并做首尾交叉淡化后的循环片段滤镜链。 */
function loopFilter(): string {
  const head = `[0:v]trim=0:${LOOP_XFADE},setpts=PTS-STARTPTS[head]`;
  const body = `[0:v]trim=${LOOP_XFADE}:${LOOP_LEN + LOOP_XFADE},setpts=PTS-STARTPTS[body]`;
  const blend = `[body][head]xfade=transition=fade:duration=${LOOP_XFADE}:offset=${LOOP_LEN - LOOP_XFADE}[loop]`;
  const scale = `[loop]fps=${LOOP_FPS},scale=${LOOP_WIDTH}:-2:flags=lanczos[out]`;
  return [head, body, blend, scale].join(';');
}

const loopInput = ['-ss', LOOP_START.toFixed(3), '-t', (LOOP_LEN + LOOP_XFADE).toFixed(3), '-i', FRAMES];

function hasFfmpegWebp(): boolean {
  const encoders = execFileSync('ffmpeg', ['-hide_banner', '-encoders'], {encoding: 'utf8'});
  return /\blibwebp\b/.test(encoders);
}

/** 优先用 ffmpeg 的 libwebp；Homebrew 默认 ffmpeg 不带它时，退回 libwebp 自带的 img2webp。 */
function encodeLoop(): void {
  if (hasFfmpegWebp()) {
    ffmpeg([
      ...loopInput, '-filter_complex', loopFilter(), '-map', '[out]', '-an',
      '-c:v', 'libwebp', '-lossless', '0', '-q:v', String(LOOP_QUALITY),
      '-compression_level', '6', '-preset', 'drawing', '-loop', '0', LOOP,
    ]);
  } else {
    const dir = mkdtempSync(join(tmpdir(), 'mivibe-loop-'));
    try {
      ffmpeg([...loopInput, '-filter_complex', loopFilter(), '-map', '[out]', '-an', join(dir, 'f%04d.png')]);
      const frames = readdirSync(dir).filter(f => f.endsWith('.png')).sort().map(f => join(dir, f));
      execFileSync('img2webp', [
        '-loop', '0', '-min_size', '-lossy', '-q', String(LOOP_QUALITY), '-m', '6',
        '-d', String(Math.round(1000 / LOOP_FPS)), ...frames, '-o', LOOP,
      ], {stdio: ['ignore', 'ignore', 'inherit']});
    } finally {
      rmSync(dir, {recursive: true, force: true});
    }
  }
  console.log(`loop  → output/mivibe-loop.webp (${mb(LOOP)} MB)`);
}

requireFile(FRAMES, 'pnpm frames');
requireFile(MUSIC, 'pnpm music');
muxVideo();
encodeLoop();
