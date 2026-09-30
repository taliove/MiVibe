/**
 * 场景 1（0–4 s，8 拍）：黑场里遥控器浮现，第 2 拍语音键亮起潮汐青并泛起声波涟漪；
 * 标题「按住，说话。」在第 4 拍（2 s）前后推入。
 */
import {Circle, Node, makeScene2D} from '@motion-canvas/2d';
import {all, createRef, createSignal, easeOutCubic, easeInOutCubic, type ThreadGenerator} from '@motion-canvas/core';
import {TIDE} from '../brand/colors.ts';
import {INTRO} from '../copy.ts';
import {section} from '../timing.ts';
import {Backdrop} from '../components/Backdrop.tsx';
import {createCaption} from '../components/Caption.tsx';
import {Remote, keyPoint} from '../components/Remote.tsx';
import {at, endScene} from '../components/beat.ts';

const REMOTE_H = 820;

export default makeScene2D(function* (view) {
  const glow = createSignal(0);
  const lit = createSignal(0);
  const stage = createRef<Node>();
  const rig = createRef<Node>();
  const ripples = createRef<Node>();
  const caption = createCaption({cn: INTRO.headline, en: INTRO.sub, x: -150, y: -10, size: 150, align: -1});
  const [kx, ky] = keyPoint('voice', REMOTE_H / 290);

  view.add(
    <Node ref={stage}>
      <Backdrop glow={glow} glowY={-40} grid={() => 0.4 + 0.6 * glow()} />
      <Node ref={rig} x={-540} y={60} rotation={-9} opacity={0}>
        <Remote height={REMOTE_H} lit={lit} />
        <Node ref={ripples} x={kx} y={ky} />
      </Node>
      {caption.node}
    </Node>,
  );

  function* ripple(): ThreadGenerator {
    const ring = createRef<Circle>();
    ripples().add(<Circle ref={ring} size={60} stroke={TIDE.accentDark} lineWidth={4} opacity={0.9} />);
    yield* all(ring().size(520, 1.2, easeOutCubic), ring().lineWidth(0.5, 1.2), ring().opacity(0, 1.2));
    ring().remove();
  }

  // 第 0 拍：遥控器从黑暗中浮现。
  yield all(rig().opacity(1, 1.1, easeOutCubic), rig().y(20, 2.0, easeOutCubic));
  // 第 2 拍：语音键亮起（配乐同一拍有一声「叮」）。
  yield at(2, function* () {
    yield* all(lit(1, 0.12), glow(1, 0.8, easeOutCubic));
  });
  // 每拍一圈涟漪：声音从语音键扩散出去。
  for (const b of [2, 3, 4, 5, 6, 7]) yield at(b, ripple);
  // 标题在第 4 拍落定。
  yield at(3.5, () => caption.reveal(0.2));
  // 最后一小节轻推镜头，把能量交给下一段。
  yield at(6, () => stage().scale(1.05, 1.0, easeInOutCubic));

  yield* endScene(section('intro').lengthBeats);
});
