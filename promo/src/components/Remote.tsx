/**
 * 小米蓝牙语音遥控器（矢量），几何逐项取自 Sources/MiVibe/UI/RemoteControlView.swift：
 * 机身宽 100 单位、高 290 单位，按键给出中心点与直径；这里把原点移到机身中心。
 * lit：语音键亮起程度 0…1；flash：各可映射键的高亮信号（按键映射卡片用）。
 */
import {Circle, Gradient, Line, Node, Rect} from '@motion-canvas/2d';
import {Color, createSignal, type SimpleSignal} from '@motion-canvas/core';
import {TIDE} from '../brand/colors.ts';

export type RemoteKey = 'up' | 'down' | 'left' | 'right' | 'confirm' | 'back' | 'home' | 'menu' | 'volumeUp' | 'volumeDown' | 'tv';

const W = 100;
const H = 290;
const PAD = {x: 50, y: 93, ring: 82, center: 43};
const ARM = (PAD.ring + PAD.center) / 4;
const COL = {left: 29, right: 71};
const ROWS = [154, 192, 230];
const KEY_D = 32;

/** 键位中心（机身中心为原点，单位坐标）。 */
export const KEY_POS: Record<RemoteKey | 'voice' | 'power', {x: number; y: number; d: number}> = {
  power: {x: 25, y: 30, d: 23},
  voice: {x: 75, y: 30, d: 23},
  up: {x: PAD.x, y: PAD.y - ARM, d: 20},
  down: {x: PAD.x, y: PAD.y + ARM, d: 20},
  left: {x: PAD.x - ARM, y: PAD.y, d: 20},
  right: {x: PAD.x + ARM, y: PAD.y, d: 20},
  confirm: {x: PAD.x, y: PAD.y, d: PAD.center},
  back: {x: COL.left, y: ROWS[0], d: KEY_D},
  home: {x: COL.left, y: ROWS[1], d: KEY_D},
  menu: {x: COL.left, y: ROWS[2], d: KEY_D},
  volumeUp: {x: COL.right, y: ROWS[0], d: KEY_D},
  volumeDown: {x: COL.right, y: ROWS[1], d: KEY_D},
  tv: {x: COL.right, y: ROWS[2], d: KEY_D},
};

/** 键位中心换算成遥控器局部像素坐标。 */
export function keyPoint(key: keyof typeof KEY_POS, unit: number): [number, number] {
  const p = KEY_POS[key];
  return [(p.x - W / 2) * unit, (p.y - H / 2) * unit];
}

const grey = (w: number) => {
  const v = Math.round(w * 255).toString(16).padStart(2, '0');
  return `#${v}${v}${v}`;
};
const ALUMINIUM = [0.7, 0.86, 0.93, 0.87, 0.68].map(grey);
const DARK_KEY = [grey(0.27), grey(0.13)];

const hGradient = (colors: string[], w: number) =>
  new Gradient({
    type: 'linear', from: [-w / 2, 0], to: [w / 2, 0],
    stops: colors.map((color, i) => ({offset: i / (colors.length - 1), color})),
  });
const vGradient = (colors: string[], h: number) =>
  new Gradient({
    type: 'linear', from: [0, -h / 2], to: [0, h / 2],
    stops: colors.map((color, i) => ({offset: i / (colors.length - 1), color})),
  });

/** 语音键亮起时的柔和光晕。 */
const halo = (color: string, r: number) =>
  new Gradient({
    type: 'radial', from: [0, 0], to: [0, 0], fromRadius: 0, toRadius: r,
    stops: [[0, 0.7], [0.35, 0.45], [0.6, 0.18], [0.8, 0.05], [1, 0]].map(([offset, a]) => ({
      offset, color: new Color(color).alpha(a),
    })),
  });

/** 简化的按键符号（替代 SF Symbols），d 为按键直径（单位坐标）。 */
function Glyph({name, d, color}: {name: string; d: number; color: string}): Node {
  const s = d * 0.36;
  const lw = Math.max(1.1, d * 0.06);
  const common = {stroke: color, lineWidth: lw, lineCap: 'round' as const, lineJoin: 'round' as const};
  switch (name) {
    case 'power':
      return (<Node><Circle size={s} startAngle={-60} endAngle={240} {...common} /><Line points={[[0, -s * 0.62], [0, -s * 0.08]]} {...common} /></Node>) as Node;
    case 'mic':
      return (
        <Node>
          <Rect width={s * 0.42} height={s * 0.7} radius={s * 0.21} y={-s * 0.2} {...common} />
          <Circle size={s * 0.85} startAngle={0} endAngle={180} y={-s * 0.1} {...common} />
          <Line points={[[0, s * 0.33], [0, s * 0.55]]} {...common} />
        </Node>
      ) as Node;
    case 'back':
      return (<Line points={[[s * 0.18, -s * 0.4], [-s * 0.22, 0], [s * 0.18, s * 0.4]]} {...common} />) as Node;
    case 'home':
      return (<Line points={[[-s * 0.45, 0], [0, -s * 0.45], [s * 0.45, 0], [s * 0.32, 0], [s * 0.32, s * 0.42], [-s * 0.32, s * 0.42], [-s * 0.32, 0]]} closed {...common} />) as Node;
    case 'menu':
      return (<Node>{[-0.3, 0, 0.3].map(y => <Line points={[[-s * 0.45, y * s], [s * 0.45, y * s]]} {...common} />)}</Node>) as Node;
    case 'volumeUp':
      return (<Node><Line points={[[-s * 0.4, 0], [s * 0.4, 0]]} {...common} /><Line points={[[0, -s * 0.4], [0, s * 0.4]]} {...common} /></Node>) as Node;
    case 'volumeDown':
      return (<Line points={[[-s * 0.4, 0], [s * 0.4, 0]]} {...common} />) as Node;
    case 'tv':
      return (<Node><Rect width={s * 1.0} height={s * 0.7} radius={s * 0.1} y={-s * 0.08} {...common} /><Line points={[[-s * 0.25, s * 0.45], [s * 0.25, s * 0.45]]} {...common} /></Node>) as Node;
    default:
      return (<Circle size={2} fill={color} />) as Node;
  }
}

export interface RemoteProps {
  /** 机身高度（像素）。 */
  readonly height: number;
  readonly lit?: SimpleSignal<number>;
  readonly flash?: Partial<Record<RemoteKey, SimpleSignal<number>>>;
  readonly accent?: string;
}

export function Remote({height, lit = createSignal(0), flash = {}, accent = TIDE.accentDark}: RemoteProps): Node {
  const unit = height / H;
  const place = (key: keyof typeof KEY_POS) => {
    const [x, y] = keyPoint(key, 1);
    return {x, y};
  };
  const silver = (key: 'power' | 'voice', glyph: string) => {
    const p = KEY_POS[key];
    const isVoice = key === 'voice';
    return (
      <Node {...place(key)}>
        {isVoice && <Circle size={p.d * 3.2} fill={halo(accent, p.d * 1.6)} opacity={lit} />}
        <Circle size={p.d} fill={vGradient([...ALUMINIUM].reverse(), p.d)} stroke={grey(0.42)} lineWidth={1.2} />
        {isVoice && <Circle size={p.d} fill={accent} opacity={lit} />}
        <Glyph name={glyph} d={p.d} color={grey(0.25)} />
        {isVoice && <Node opacity={lit}><Glyph name={glyph} d={p.d} color={'#FFFFFF'} /></Node>}
      </Node>
    );
  };
  const mappable = (key: RemoteKey, glyph: string | null, face: 'cap' | 'center' | 'onBase') => {
    const p = KEY_POS[key];
    const f = flash[key] ?? createSignal(0);
    return (
      <Node {...place(key)}>
        {face === 'cap' && <Circle size={p.d} fill={vGradient(DARK_KEY, p.d)} stroke={'rgba(255,255,255,0.08)'} lineWidth={1} />}
        {face === 'center' && <Circle size={p.d} fill={grey(0.17)} stroke={'rgba(0,0,0,0.45)'} lineWidth={1} />}
        <Circle size={p.d} fill={accent} opacity={() => 0.9 * f()} />
        <Circle size={p.d} stroke={'rgba(255,255,255,0.9)'} lineWidth={1.2} opacity={f} />
        {glyph ? <Glyph name={glyph} d={p.d} color={'#FFFFFF'} /> : <Circle size={2} fill={'rgba(255,255,255,0.6)'} />}
      </Node>
    );
  };
  const volY = (ROWS[0] + ROWS[1]) / 2 - H / 2;
  return (
    <Node scale={unit}>
      <Rect
        width={W} height={H} radius={11} smoothCorners fill={hGradient(ALUMINIUM, W)}
        stroke={'rgba(0,0,0,0.18)'} lineWidth={1}
        shadowColor={'rgba(0,0,0,0.6)'} shadowBlur={30} shadowOffset={[0, 12]}
      />
      <Rect width={W} height={H} radius={11} smoothCorners fill={vGradient(['rgba(0,0,0,0)', 'rgba(0,0,0,0)', 'rgba(0,0,0,0.38)'], H)} />
      {silver('power', 'power')}
      {silver('voice', 'mic')}
      <Circle {...place('confirm')} size={PAD.ring} fill={vGradient(DARK_KEY, PAD.ring)} />
      <Rect x={COL.right - W / 2} y={volY} width={KEY_D} height={ROWS[1] - ROWS[0] + KEY_D} radius={KEY_D / 2} fill={vGradient(DARK_KEY, 70)} />
      <Rect x={0} y={262 - H / 2} width={8} height={8} radius={1.5} fill={grey(0.45)} />
      {mappable('up', null, 'onBase')}
      {mappable('down', null, 'onBase')}
      {mappable('left', null, 'onBase')}
      {mappable('right', null, 'onBase')}
      {mappable('confirm', null, 'center')}
      {mappable('back', 'back', 'cap')}
      {mappable('home', 'home', 'cap')}
      {mappable('menu', 'menu', 'cap')}
      {mappable('volumeUp', 'volumeUp', 'onBase')}
      {mappable('volumeDown', 'volumeDown', 'onBase')}
      {mappable('tv', 'tv', 'cap')}
    </Node>
  ) as Node;
}
