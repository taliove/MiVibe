/**
 * 成片自检：node scripts/check.ts
 *
 * 1. 切点 vs 节拍：在每个预期切点附近用 ffmpeg 场景检测找真实切帧，列出偏差（帧）。
 * 2. 抽帧：把代表性时间点导出到 output/stills/，便于人工检查排版、CJK 字形、溢出。
 * 3. 响度：ebur128 积分响度与真峰值、时长、文件大小。
 */
import {execFileSync, spawnSync} from 'node:child_process';
import {mkdirSync, statSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {
  BEAT, FEATURE_CARD_BEATS, FEATURE_CARD_COUNT, FPS, SECTIONS, THEME_SWITCH_BEATS, beats, section,
} from '../src/timing.ts';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const VIDEO = join(ROOT, 'output', 'mivibe-promo.mp4');
const STILLS = join(ROOT, 'output', 'stills');
const WINDOW = 0.25; // 在预期切点前后多少秒内找切帧

const run = (args: string[]) =>
  execFileSync('ffmpeg', ['-hide_banner', ...args], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe']});
/** ffmpeg 的滤镜统计都写在 stderr：一并收集返回。 */
const runAll = (args: string[]) => {
  const res = spawnSync('ffmpeg', ['-hide_banner', ...args], {encoding: 'utf8'});
  if (res.error) throw res.error;
  return `${res.stdout}\n${res.stderr}`;
};

interface Cut {
  readonly label: string;
  readonly beat: number;
  readonly threshold: number;
  /** hard：硬切，取窗口内变化最大的一帧；onset：渐变，取第一帧开始变化的帧。 */
  readonly mode: 'hard' | 'onset';
}

function expectedCuts(): Cut[] {
  const sectionCuts = SECTIONS.slice(1).map(s => ({label: `段落 → ${s.id}`, beat: s.startBeat, threshold: 0.05, mode: 'hard' as const}));
  const f = section('features').startBeat;
  const cards = Array.from({length: FEATURE_CARD_COUNT}, (_, i) => i)
    .slice(1)
    .map(i => ({label: `功能卡 ${i + 1}`, beat: f + i * FEATURE_CARD_BEATS, threshold: 0.02, mode: 'hard' as const}));
  const recap = {label: '功能总览', beat: f + FEATURE_CARD_BEATS * FEATURE_CARD_COUNT, threshold: 0.05, mode: 'hard' as const};
  const t = section('themes').startBeat;
  const themes = THEME_SWITCH_BEATS.map((b, i) => ({label: `换主题 ${i + 1}`, beat: t + b, threshold: 0.002, mode: 'onset' as const}));
  return [...sectionCuts, ...cards, recap, ...themes].sort((a, b) => a.beat - b.beat);
}

/** 在 [t-WINDOW, t+WINDOW] 内找画面变化最大的一帧，返回其全片帧号。 */
function detectCut(time: number, threshold: number, mode: Cut['mode']): number | null {
  const start = Math.max(0, time - WINDOW);
  const out = runAll([
    '-ss', start.toFixed(3), '-t', (WINDOW * 2).toFixed(3), '-i', VIDEO,
    '-vf', `select='gt(scene,${threshold})',metadata=print`, '-an', '-f', 'null', '-',
  ]);
  const hits = [...out.matchAll(/pts_time:([\d.]+)[\s\S]*?scene_score=([\d.]+)/g)]
    .map(m => ({t: Number(m[1]), score: Number(m[2])}));
  if (hits.length === 0) return null;
  const onset = hits.find(h => h.t >= WINDOW - 2 / FPS);
  const best = mode === 'onset' ? onset ?? hits[0] : hits.reduce((a, b) => (b.score > a.score ? b : a));
  return Math.round((start + best.t) * FPS);
}

function beatTable(): void {
  console.log('\n切点 vs 节拍网格（120 BPM，1 拍 = 30 帧）');
  console.log('| 切点 | 拍 | 预期时间 (s) | 预期帧 | 实测帧 | 偏差 |');
  console.log('| --- | --- | --- | --- | --- | --- |');
  for (const cut of expectedCuts()) {
    const time = beats(cut.beat);
    const expected = Math.round(time * FPS);
    const actual = detectCut(time, cut.threshold, cut.mode);
    const delta = actual === null ? '未检出' : `${actual - expected >= 0 ? '+' : ''}${actual - expected}`;
    console.log(`| ${cut.label} | ${cut.beat} | ${time.toFixed(3)} | ${expected} | ${actual ?? '—'} | ${delta} |`);
  }
}

const STILL_TIMES: ReadonlyArray<readonly [string, number]> = [
  ['01-intro', beats(7)],
  ['02-pipeline-correct', beats(section('pipeline').startBeat + 9.6)],
  ['03-pipeline-inserted', beats(section('pipeline').startBeat + 17)],
  ['04-feature-offline', beats(section('features').startBeat + 3)],
  ['05-feature-keys', beats(section('features').startBeat + 11)],
  ['06-recap', beats(section('features').startBeat + 30)],
  ['07-themes', beats(section('themes').startBeat + 9)],
  ['08-outro', beats(section('outro').startBeat + 6)],
];

function extractStills(): void {
  mkdirSync(STILLS, {recursive: true});
  for (const [name, time] of STILL_TIMES) {
    run(['-loglevel', 'error', '-y', '-ss', time.toFixed(3), '-i', VIDEO, '-frames:v', '1', join(STILLS, `${name}.png`)]);
  }
  console.log(`\n抽帧 → output/stills/（${STILL_TIMES.map(([n, t]) => `${n}@${t.toFixed(2)}s`).join('，')}）`);
}

function loudness(): void {
  const out = runAll(['-nostats', '-i', VIDEO, '-af', 'ebur128=peak=true', '-f', 'null', '-']);
  const lufs = out.match(/I:\s+(-?[\d.]+) LUFS/g)?.pop();
  const peak = out.match(/Peak:\s+(-?[\d.]+) dBFS/g)?.pop();
  const probe = execFileSync('ffprobe', [
    '-v', 'error', '-show_entries', 'format=duration:stream=codec_name,width,height,r_frame_rate,pix_fmt',
    '-of', 'compact', VIDEO,
  ], {encoding: 'utf8'});
  console.log(`\n响度：${lufs ?? '?'}，真峰值 ${peak ?? '?'}`);
  console.log(`文件：${(statSync(VIDEO).size / 1024 / 1024).toFixed(2)} MB`);
  console.log(probe.trim());
  console.log(`节拍：${BEAT}s/拍`);
}

beatTable();
extractStills();
loudness();
