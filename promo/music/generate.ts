/**
 * 配乐生成入口：node music/generate.ts
 *
 * 120 BPM、48 kHz、16-bit 立体声，写到 music/out/soundtrack.wav。
 * 全部离线逐采样合成、带固定种子，重复运行得到逐字节相同的文件，零版权风险。
 */
import {mkdirSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {BEAT, DURATION, FADE_BEATS, FADE_START_BEAT, BPM} from '../src/timing.ts';
import {arrange, sidechainCurve} from './arrangement.ts';
import {type Stereo, dbToGain, makeStereo, mixStereo, pingPong, reverb} from './dsp.ts';
import {applyGain, busGlue, fadeOut, integratedLoudness, limit, peakDb, writeWav} from './master.ts';

const TARGET_LUFS = -14;
const CEILING_DB = -1;
const OUT = join(dirname(fileURLToPath(import.meta.url)), 'out', 'soundtrack.wav');

function duck(bus: Stereo, curve: Float32Array): Stereo {
  return {left: bus.left.map((v, i) => v * curve[i]), right: bus.right.map((v, i) => v * curve[i])};
}

function mixdown(): Stereo {
  const started = Date.now();
  const buses = arrange(DURATION);
  console.log(`arranged in ${((Date.now() - started) / 1000).toFixed(1)} s`);

  const sidechain = sidechainCurve(buses.kicks, DURATION, 0.55);
  const pad = duck(buses.pad, sidechain);
  const bassBus = duck(buses.bass, sidechainCurve(buses.kicks, DURATION, 0.7));
  const arp = duck(buses.arp, sidechain);

  // 发送效果：铺底与琶音进混响，琶音再进附点八分乒乓延迟。
  const send = makeStereo(DURATION);
  mixStereo(send, pad, 0.6);
  mixStereo(send, arp, 0.8);
  mixStereo(send, buses.fx, 0.5);
  const verb = reverb(send);
  const delay = pingPong(arp, BEAT * 0.75, 0.38);

  const mix = makeStereo(DURATION);
  mixStereo(mix, buses.drums, 1.0);
  mixStereo(mix, bassBus, 0.9);
  mixStereo(mix, pad, 0.55);
  mixStereo(mix, arp, 0.7);
  mixStereo(mix, buses.fx, 0.75);
  mixStereo(mix, verb, 0.45);
  mixStereo(mix, delay, 0.3);
  return mix;
}

function master(raw: Stereo): Stereo {
  let mix = busGlue(applyGain(raw, dbToGain(-6)));
  // 限幅会吃掉一点响度：先归一、再限幅、再微调一次。
  for (let pass = 0; pass < 2; pass++) {
    const lufs = integratedLoudness(mix);
    mix = limit(applyGain(mix, dbToGain(TARGET_LUFS - lufs)), CEILING_DB);
  }
  return fadeOut(mix, FADE_START_BEAT * BEAT, FADE_BEATS * BEAT);
}

const mastered = master(mixdown());
mkdirSync(dirname(OUT), {recursive: true});
writeWav(OUT, mastered);
console.log(
  `${BPM} BPM · ${DURATION.toFixed(2)} s · ${integratedLoudness(mastered).toFixed(1)} LUFS · ` +
    `peak ${peakDb(mastered).toFixed(2)} dBFS → music/out/soundtrack.wav`,
);
