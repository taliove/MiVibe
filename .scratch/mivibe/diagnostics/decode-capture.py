"""Offline diagnostic: decode observed ATVV 1.0 ADPCM using Python's IMA codec."""
import audioop
import json
import os
import struct
import sys
import wave
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
events = json.loads(source.read_text())
state = (0, 0)
started = False
parts = []
frames = 0
sizes = set()
syncs = 0
stopped = False
for event in events:
    raw = bytes.fromhex(event['hex'])
    if event['kind'] == 'control':
        if raw[:1] == b'\x04':
            if len(raw) < 4 or raw[2] != 2:
                raise ValueError('Expected verified 16 kHz ADPCM AUDIO_START')
            started = True
            state = (0, 0)
        elif raw[:1] == b'\x0a' and started:
            if len(raw) < 7 or raw[1] != 2 or raw[6] > 88:
                raise ValueError('Unsupported SYNC')
            state = (struct.unpack('>h', raw[4:6])[0], raw[6])
            syncs += 1
        elif raw[:1] == b'\x00' and started:
            stopped = True
    elif event['kind'] == 'audio':
        if not started:
            raise ValueError('Audio before AUDIO_START')
        pcm, state = audioop.adpcm2lin(raw, 2, state)
        parts.append(pcm)
        frames += 1
        sizes.add(len(raw))
if not parts:
    raise ValueError('No audio captured')
pcm = b''.join(parts)
fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, 'wb') as out:
    with wave.open(out, 'wb') as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        wav.writeframes(pcm)
print(json.dumps(dict(frames=frames, frame_bytes=sorted(sizes), syncs=syncs,
    protocol_stop=stopped, seconds=len(pcm)/32000, rms=audioop.rms(pcm,2),
    peak=audioop.max(pcm,2), output=str(target)),ensure_ascii=False))
