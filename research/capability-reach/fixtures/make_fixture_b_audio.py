#!/usr/bin/env python3
"""Fixture B：虚构公开音频 → 转写 / 摘要。

全虚构，无真实个人数据、无真实录音（`DATA_BOUNDARY.md` §4）。
音频由本机 TTS 合成（edge-tts，微软公开端点，无 key、无生产凭据），内容是我们自己写的虚构句子。

故意埋的易错点：
  8/3           "八千三百"（8300）与"三号"
  中文数字 vs 阿拉伯数字   口述是中文数字，用户要的是能用的数字
  0/O           "零是零，不是字母欧"
  长数字串       "一三八零零一三一零零八"（13800131008）
  小数点        "一百零三点五"（103.5）
  同音          零 / 欧

用法：
  python make_fixture_b_audio.py --model <model.int8.onnx> --tokens <tokens.txt> \
         --wav out/fixture_b_16k.wav
"""

import argparse
import wave
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent
OUT = HERE / "out"

# Ground truth：这是喂给 TTS 的原句，作为比对基准。
SCRIPT_TEXT = (
    "这是一段虚构的测试音频。本月三号，我借给张伟八千三百元。"
    "另外买了两袋水泥，花了一百零三点五元。"
    "联系电话是一三八零零一三一零零八。记着，零是零，不是字母欧。"
)


def read_wave(path):
    with wave.open(str(path)) as f:
        assert f.getsampwidth() == 2, "需要 16bit PCM"
        n = f.getnframes()
        raw = f.readframes(n)
    arr = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    if f.getnchannels() == 2:
        arr = arr.reshape(-1, 2).mean(axis=1)
    return arr, f.getframerate()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--tokens", required=True)
    ap.add_argument("--wav", default=str(OUT / "fixture_b_16k.wav"))
    args = ap.parse_args()

    print("=== GROUND TRUTH（喂给 TTS 的原句）===")
    print(SCRIPT_TEXT)

    import sherpa_onnx

    rec = sherpa_onnx.OfflineRecognizer.from_paraformer(
        paraformer=args.model,
        tokens=args.tokens,
        num_threads=2,
        sample_rate=16000,
        feature_dim=80,
        decoding_method="greedy_search",
    )
    samples, sr = read_wave(args.wav)
    print(f"\nAUDIO: {args.wav}  sr={sr}  samples={len(samples)}")

    stream = rec.create_stream()
    stream.accept_waveform(sr, samples)
    rec.decode_stream(stream)
    text = stream.result.text

    print("\n=== ASR OUTPUT ===")
    print(text)

    # 数字提取（很朴素：把连续数字串抓出来）
    import re

    nums = re.findall(r"\d+", text)
    print("\n=== 抓到的数字串 ===")
    print(nums if nums else "（无）")

    out = OUT / "fixture_b_asr_output.txt"
    out.write_text(
        f"GROUND TRUTH\n{SCRIPT_TEXT}\n\nAUDIO: {args.wav}\n\nASR OUTPUT\n{text}\n\n数字串: {nums}\n",
        encoding="utf-8",
    )
    print(f"\nSAVED: {out}")


if __name__ == "__main__":
    main()
