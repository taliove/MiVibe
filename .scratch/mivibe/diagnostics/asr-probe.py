#!/usr/bin/env python3
"""MiVibe 豆包流式 ASR 实测探针（08 票取证工具）。

用途：用本地凭据对 2.0 小时版资源做小样验证，裁决协议残留分歧并测量尾延迟。
对应取证清单见 .scratch/mivibe/research/doubao-wire.md「实测待取证清单」。

凭据：只从环境变量或 macOS Keychain 读取，绝不写入仓库/聊天/日志：
    export VOLC_API_KEY='...'            # 方式一：环境变量
    security add-generic-password -s mivibe-volc-apikey -a "$USER" -w '...'   # 方式二：Keychain
    export VOLC_RESOURCE_ID='volc.seedasr.sauc.duration'   # 可选，默认 2.0 小时版

费用护栏：每次运行把发送的音频时长（云端按时长计费）追加到
    diagnostics/asr-usage.jsonl；累计折算费用超过 --cap-yuan（默认 5 元）时拒绝运行。

用法（推荐 uv，免装依赖）：
    uv run --with websockets asr-probe.py handshake            # 只验握手+首包，基本零费用
    uv run --with websockets asr-probe.py run --say "测试文本"  # macOS say 生成测试音频
    uv run --with websockets asr-probe.py run --audio a.wav    # 用自备授权音频
    uv run --with websockets asr-probe.py run --say "..." --nonstream   # 开二遍识别测尾延迟
    uv run --with websockets asr-probe.py cancel --say "..."   # 中途 abrupt 断开观察行为

证据输出：diagnostics/asr-evidence-<UTC时间戳>.jsonl，含首/末响应原始帧 hex 与解析结果。
"""

import argparse
import gzip
import json
import os
import struct
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

WS_URL = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async"
DEFAULT_RESOURCE_ID = "volc.seedasr.sauc.duration"  # 2.0 小时版
PRICE_YUAN_PER_HOUR = 1.0                            # 2.0 流式官方刊例价
SEGMENT_MS = 200
PCM_BYTES_PER_SEG = 16000 * 2 * SEGMENT_MS // 1000   # 6400 字节
DIAG_DIR = Path(__file__).resolve().parent
USAGE_LEDGER = DIAG_DIR / "asr-usage.jsonl"

# 帧协议常量（与官方 veadk-python SDK / sauc 示例一致）
PROTOCOL_VERSION = 0b0001
MSG_FULL_REQUEST = 0b0001
MSG_AUDIO_ONLY = 0b0010
MSG_SERVER_FULL = 0b1001
MSG_SERVER_ERROR = 0b1111
FLAG_POS_SEQ = 0b0001
FLAG_LAST_NO_SEQ = 0b0010
FLAG_NEG_SEQ_LAST = 0b0011
SER_JSON = 0b0001
SER_NONE = 0b0000
COMP_GZIP = 0b0001
COMP_NONE = 0b0000


def build_header(msg_type: int, flags: int, serial: int, comp: int) -> bytes:
    return bytes([
        (PROTOCOL_VERSION << 4) | 1,
        (msg_type << 4) | flags,
        (serial << 4) | comp,
        0x00,
    ])


def build_full_request(seq: int, nonstream: bool) -> bytes:
    payload = {
        "user": {"uid": "mivibe-probe"},
        "audio": {"format": "pcm", "codec": "raw", "rate": 16000, "bits": 16, "channel": 1},
        "request": {
            "model_name": "bigmodel",
            "enable_itn": True,
            "enable_punc": True,
            "enable_ddc": True,
            "show_utterances": True,
            "result_type": "full",
            "enable_nonstream": nonstream,
        },
    }
    blob = gzip.compress(json.dumps(payload).encode("utf-8"))
    return (
        build_header(MSG_FULL_REQUEST, FLAG_POS_SEQ, SER_JSON, COMP_GZIP)
        + struct.pack(">i", seq)
        + struct.pack(">I", len(blob))
        + blob
    )


def build_audio_packet(seq: int, pcm: bytes, is_last: bool) -> bytes:
    flags, out_seq = (FLAG_NEG_SEQ_LAST, -seq) if is_last else (FLAG_POS_SEQ, seq)
    blob = gzip.compress(pcm)  # 末包约定为 gzip 压缩的空字节
    return (
        build_header(MSG_AUDIO_ONLY, flags, SER_NONE, COMP_GZIP)
        + struct.pack(">i", out_seq)
        + struct.pack(">I", len(blob))
        + blob
    )


def parse_frame(raw: bytes) -> dict:
    """按官方 SDK 解析；保留原始位级字段供裁决 flags 0x04 等分歧。"""
    header_size = raw[0] & 0x0F
    msg_type = raw[1] >> 4
    flags = raw[1] & 0x0F
    serial = raw[2] >> 4
    comp = raw[2] & 0x0F
    body = raw[header_size * 4:]

    out = {
        "msg_type": msg_type,
        "flags": flags,
        "has_seq": bool(flags & 0x01),
        "is_last_package": bool(flags & 0x02),
        "has_event_field": bool(flags & 0x04),
        "serialization": serial,
        "compression": comp,
    }
    if flags & 0x01:
        out["sequence"] = struct.unpack(">i", body[:4])[0]
        body = body[4:]
    if flags & 0x04:
        out["event"] = struct.unpack(">i", body[:4])[0]
        body = body[4:]

    if msg_type == MSG_SERVER_FULL:
        out["payload_size"] = struct.unpack(">I", body[:4])[0]
        body = body[4:]
    elif msg_type == MSG_SERVER_ERROR:
        out["code"] = struct.unpack(">i", body[:4])[0]
        out["payload_size"] = struct.unpack(">I", body[4:8])[0]
        body = body[8:]

    if body:
        raw_payload = body
        try:
            if comp == COMP_GZIP:
                body = gzip.decompress(body)
            out["payload_json"] = json.loads(body.decode("utf-8")) if serial == SER_JSON else None
            out["payload_len_compressed"] = len(raw_payload)
            out["payload_len_plain"] = len(body)
        except Exception as e:  # 探针永不在异常帧上崩溃：异常本身即证据
            out["payload_error"] = f"{type(e).__name__}: {e}"
            out["payload_hex"] = raw_payload[:64].hex()
    return out


class Evidence:
    """JSONL 证据记录：首/末响应保留原始帧 hex，绝不记录凭据。"""

    def __init__(self, label: str):
        ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        self.path = DIAG_DIR / f"asr-evidence-{label}-{ts}.jsonl"
        self.t0 = time.monotonic()

    def log(self, kind: str, data: dict):
        rec = {"t": round(time.monotonic() - self.t0, 3), "kind": kind, **data}
        with open(self.path, "a") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        return rec


def load_usage_seconds() -> float:
    if not USAGE_LEDGER.exists():
        return 0.0
    total = 0.0
    for line in USAGE_LEDGER.read_text().splitlines():
        try:
            total += json.loads(line).get("audio_seconds", 0.0)
        except json.JSONDecodeError:
            continue
    return total


def check_cost_guard(cap_yuan: float, planned_seconds: float) -> None:
    used_s = load_usage_seconds()
    used_yuan = used_s / 3600 * PRICE_YUAN_PER_HOUR
    planned_yuan = planned_seconds / 3600 * PRICE_YUAN_PER_HOUR
    if used_yuan + planned_yuan > cap_yuan:
        print(
            f"[护栏] 累计 {used_yuan:.4f} 元 + 本次预计 {planned_yuan:.4f} 元 "
            f"将超过上限 {cap_yuan} 元，拒绝运行。",
            file=sys.stderr,
        )
        sys.exit(3)
    print(f"[护栏] 累计已用 {used_yuan:.4f} 元 / 上限 {cap_yuan} 元，本次预计 {planned_yuan:.4f} 元")


def record_usage(audio_seconds: float, mode: str) -> None:
    rec = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "mode": mode,
        "audio_seconds": round(audio_seconds, 3),
        "est_yuan": round(audio_seconds / 3600 * PRICE_YUAN_PER_HOUR, 6),
    }
    with open(USAGE_LEDGER, "a") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def wav_to_pcm(path: Path) -> bytes:
    """读取 WAV（RIFF）取 data 块；非 16k/mono/s16le 时用 afconvert 转换。"""
    data = path.read_bytes()
    if len(data) < 44 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError(f"{path} 不是 WAV 文件；请提供 WAV 或用 --say 生成")
    channels = struct.unpack("<H", data[22:24])[0]
    rate = struct.unpack("<I", data[24:28])[0]
    bits = struct.unpack("<H", data[34:36])[0]
    if (rate, bits, channels) != (16000, 16, 1):
        converted = path.with_suffix(".16k.wav")
        subprocess.run(
            ["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(path), str(converted)],
            check=True,
        )
        return wav_to_pcm(converted)
    pos = 12
    while pos + 8 <= len(data):
        chunk_id, chunk_size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        if chunk_id == b"data":
            return data[pos + 8:pos + 8 + chunk_size]
        pos += 8 + chunk_size + (chunk_size & 1)
    raise ValueError(f"{path} 中找不到 data 块")


def pcm_from_say(text: str) -> bytes:
    with tempfile.NamedTemporaryFile(suffix=".aiff", delete=False) as tmp:
        aiff_path = tmp.name
    wav_path = aiff_path.replace(".aiff", ".wav")
    try:
        subprocess.run(["say", "-v", "Tingting", "-o", aiff_path, text], check=True)
        subprocess.run(
            ["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff_path, wav_path],
            check=True,
        )
        return wav_to_pcm(Path(wav_path))
    finally:
        for p in (aiff_path, wav_path):
            if os.path.exists(p):
                os.remove(p)


def get_pcm(args) -> bytes:
    if args.audio:
        return wav_to_pcm(Path(args.audio))
    return pcm_from_say(args.say or "你好，这是小米遥控器语音输入的识别测试。")


def read_api_key() -> str:
    """凭据来源优先级：环境变量 > macOS Keychain（服务名 mivibe-volc-apikey）。"""
    key = os.environ.get("VOLC_API_KEY", "").strip()
    if key:
        return key
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-s", "mivibe-volc-apikey", "-w"],
            check=True, capture_output=True, text=True,
        )
        return out.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def auth_headers() -> dict:
    key = read_api_key()
    if not key:
        print("[错误] 未找到凭据。请在终端自行配置（不要发在聊天里），二选一：\n"
              "  export VOLC_API_KEY='你的Key'\n"
              "  security add-generic-password -s mivibe-volc-apikey -a \"$USER\" -w '你的Key'",
              file=sys.stderr)
        sys.exit(2)
    return {
        "X-Api-Key": key,
        "X-Api-Resource-Id": os.environ.get("VOLC_RESOURCE_ID", DEFAULT_RESOURCE_ID).strip(),
        "X-Api-Request-Id": str(uuid.uuid4()),
    }


async def do_handshake(args) -> None:
    import websockets

    ev = Evidence("handshake")
    check_cost_guard(args.cap_yuan, 0.0)
    print(f"[连接] {WS_URL}  resource={auth_headers()['X-Api-Resource-Id']}")
    async with websockets.connect(WS_URL, additional_headers=auth_headers(),
                                  ping_interval=None, max_size=2**24) as ws:
        await ws.send(build_full_request(seq=1, nonstream=False))
        raw = await ws.recv()
        parsed = parse_frame(raw)
        ev.log("first_response", {"hex": raw.hex(), "parsed": parsed})
        print("[首响应]", json.dumps(parsed, ensure_ascii=False, indent=2))
        print(f"[证据] {ev.path}")
    record_usage(0.0, "handshake")


async def do_run(args) -> None:
    import asyncio

    import websockets

    pcm = get_pcm(args)
    audio_seconds = len(pcm) / (16000 * 2)
    ev = Evidence("nonstream" if args.nonstream else "run")
    check_cost_guard(args.cap_yuan, audio_seconds)
    print(f"[音频] {audio_seconds:.2f}s  {len(pcm)} 字节  nonstream={args.nonstream}")

    segments = [pcm[i:i + PCM_BYTES_PER_SEG] for i in range(0, len(pcm), PCM_BYTES_PER_SEG)]
    t_last_sent = None
    finals, definite_texts = [], []

    async with websockets.connect(WS_URL, additional_headers=auth_headers(),
                                  ping_interval=None, max_size=2**24) as ws:
        await ws.send(build_full_request(seq=1, nonstream=args.nonstream))
        raw = await ws.recv()
        parsed = parse_frame(raw)
        ev.log("first_response", {"hex": raw.hex(), "parsed": parsed})
        if parsed.get("payload_json", {}) and parsed["payload_json"].get("code", 1000) != 1000:
            print("[初始化失败]", json.dumps(parsed, ensure_ascii=False, indent=2))
            return

        async def send_audio():
            nonlocal t_last_sent
            seq = 2
            for seg in segments:
                await ws.send(build_audio_packet(seq, seg, is_last=False))
                seq += 1
                await asyncio.sleep(SEGMENT_MS / 1000)
            await ws.send(build_audio_packet(seq, b"", is_last=True))
            t_last_sent = time.monotonic()

        sender = asyncio.create_task(send_audio())
        try:
            async for raw in ws:
                parsed = parse_frame(raw)
                rec = ev.log("response", {"parsed": parsed})
                payload = parsed.get("payload_json") or {}
                result = payload.get("result")
                if isinstance(result, list):  # 文档表格称 list，留证据以裁决
                    ev.log("RESULT_IS_LIST", {"raw_type": "list", "value": result})
                utterances = (result or {}).get("utterances", []) if isinstance(result, dict) else []
                for u in utterances:
                    if u.get("definite"):
                        definite_texts.append(u.get("text", ""))
                        print(f"[确定 {rec['t']:6.2f}s] {u.get('text', '')}")
                if parsed["is_last_package"]:
                    ev.log("final_frame", {"hex": raw.hex(), "parsed": parsed})
                    finals.append(parsed)
                    break
        finally:
            sender.cancel()

    if t_last_sent and finals:
        print(f"[尾延迟] 末包发出 → is_last_package 到达: {round(time.monotonic() - t_last_sent, 3)}s")
    print(f"[汇总] 确定文本: {''.join(definite_texts) or '(无)'}")
    print(f"[证据] {ev.path}")
    record_usage(audio_seconds, "nonstream" if args.nonstream else "run")


async def do_cancel(args) -> None:
    """发送约 1 秒后 abrupt 断开，观察 3 秒内服务端是否还有迟到帧。"""
    import asyncio
    import websockets

    pcm = get_pcm(args)
    send_seconds = min(1.0, len(pcm) / 32000)
    ev = Evidence("cancel")
    check_cost_guard(args.cap_yuan, send_seconds)

    ws = await websockets.connect(WS_URL, additional_headers=auth_headers(),
                                  ping_interval=None, max_size=2**24)
    await ws.send(build_full_request(seq=1, nonstream=False))
    raw = await ws.recv()
    ev.log("first_response", {"hex": raw.hex(), "parsed": parse_frame(raw)})

    seq = 2
    for i in range(0, int(send_seconds * 32000), PCM_BYTES_PER_SEG):
        await ws.send(build_audio_packet(seq, pcm[i:i + PCM_BYTES_PER_SEG], is_last=False))
        seq += 1
        await asyncio.sleep(SEGMENT_MS / 1000)

    t_abort = time.monotonic()
    ws.transport.abort()  # 底层连接直接断开，模拟进程被杀/网络断开（1006 不可在线上发送）
    ev.log("abrupt_close", {"note": "transport.abort()，未发末包"})
    record_usage(send_seconds, "cancel")
    print(f"[取消] 已发送 {send_seconds:.2f}s 后 abrupt 断开。迟到帧无法在断开后接收，"
          f"本次证据用于核对控制台是否对未完成调用计费。")
    print(f"[证据] {ev.path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["handshake", "run", "cancel"])
    parser.add_argument("--audio", help="自备授权 WAV 音频路径")
    parser.add_argument("--say", help="用 macOS say 生成该文本的测试音频")
    parser.add_argument("--nonstream", action="store_true", help="开启二遍识别（enable_nonstream）")
    parser.add_argument("--cap-yuan", type=float, default=5.0, help="累计费用上限（默认 5 元）")
    args = parser.parse_args()

    import asyncio
    coro = {"handshake": do_handshake, "run": do_run, "cancel": do_cancel}[args.mode]
    asyncio.run(coro(args))


if __name__ == "__main__":
    main()
