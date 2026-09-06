"""CLI bridge for ML packages kept outside the FastAPI Python environment."""

import argparse
import json
import os
import sys
from types import SimpleNamespace

# Prevent Metal debug layer assertion crashes and Hugging Face network stalls
os.environ["MTL_DEBUG_LAYER"] = "0"
os.environ["METAL_DEVICE_WRAPPER_TYPE"] = "0"
os.environ["TOKENIZERS_PARALLELISM"] = "false"
os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "0"


def run_transcription(args: argparse.Namespace) -> int:
    from faster_whisper import WhisperModel

    compute_type = args.compute_type
    if compute_type == "float16":
        # CTranslate2 has no fp16 CPU kernel. Honour the intent of the request
        # (reduced precision, faster) with int8 rather than widening to float32,
        # which on Apple Silicon costs ~2x the memory and runs slower.
        compute_type = "int8"
    model = WhisperModel(
        args.model,
        device="cpu",
        compute_type=compute_type,
        cpu_threads=max(0, args.cpu_threads),
    )
    options = {
        "beam_size": 5,
        "word_timestamps": True,
        "vad_filter": True,
    }
    if args.language:
        options["language"] = args.language
    segments, info = model.transcribe(args.audio, **options)

    parsed_segments = []
    for index, segment in enumerate(segments, start=1):
        words = [
            {
                "word": word.word.strip(),
                "start": round(float(word.start), 3),
                "end": round(float(word.end), 3),
            }
            for word in (segment.words or [])
            if word.start is not None and word.end is not None
        ]
        start = words[0]["start"] if words else round(float(segment.start), 3)
        end = words[-1]["end"] if words else round(float(segment.end), 3)
        text = segment.text.strip()
        if not text or end <= start:
            continue
        parsed_segments.append({
            "id": index,
            "start": start,
            "end": end,
            "duration": round(end - start, 3),
            "source_text": text,
            "words": words,
        })

    with open(args.output, "w", encoding="utf-8") as output_file:
        json.dump({
            "segments": parsed_segments,
            "detected_language": getattr(info, "language", None),
            "language_probability": getattr(info, "language_probability", None),
        }, output_file, ensure_ascii=False, indent=2)
    return 0


def _is_gpu_backend_failure(error: Exception) -> bool:
    """True when a failure looks like a GPU backend fault rather than bad input.

    Torch's MPS kernels still hit Metal validation assertions on some pyannote
    graphs, and those surface as opaque shader errors that say nothing about the
    audio. Matching the backend vocabulary lets the caller retry on CPU instead of
    discarding an analysis run that already paid for transcription.
    """
    text = f"{type(error).__name__}: {error}".lower()
    markers = (
        "metal", "mps", "compute function", "failed assertion",
        "validatecomputefunctionarguments", "command buffer", "shader",
    )
    return any(marker in text for marker in markers)


def run_diarization(args: argparse.Namespace) -> int:
    import torch
    from pyannote.audio import Pipeline

    token = os.environ.get("HF_TOKEN", "").strip() or None
    model = args.model
    if not os.path.exists(model) and not token:
        raise RuntimeError(
            "A Hugging Face token is required for the first Pyannote Community-1 download. "
            "Accept the model conditions and configure the token in DubForge Settings."
        )

    device = args.device
    if device == "mps" and not torch.backends.mps.is_available():
        device = "cpu"
    elif device == "cuda" and not torch.cuda.is_available():
        device = "cpu"

    call_options = {}
    if args.num_speakers:
        call_options["num_speakers"] = args.num_speakers

    def diarize(device_name: str):
        # Rebuilt per attempt: a pipeline that faulted mid-inference cannot be
        # trusted to hold clean state, and reloading comes from the local cache.
        pipeline = Pipeline.from_pretrained(model, token=token)
        if device_name != "cpu":
            pipeline.to(torch.device(device_name))
        return pipeline(args.audio, **call_options)

    try:
        output = diarize(device)
    except Exception as error:
        if device == "cpu" or not _is_gpu_backend_failure(error):
            raise
        print(
            f"Diarization failed on {device} ({error}). Retrying on CPU.",
            file=sys.stderr,
        )
        device = "cpu"
        output = diarize(device)

    regular_annotation = getattr(output, "speaker_diarization", None) or output

    annotation = (
        getattr(output, "exclusive_speaker_diarization", None)
        or regular_annotation
    )

    regular_regions = [
        (float(turn.start), float(turn.end), str(speaker))
        for turn, _, speaker in regular_annotation.itertracks(yield_label=True)
    ]
    overlap_intervals = []
    for index, first in enumerate(regular_regions):
        for second in regular_regions[index + 1:]:
            if first[2] == second[2]:
                continue
            start = max(first[0], second[0])
            end = min(first[1], second[1])
            if end - start >= 0.08:
                overlap_intervals.append((start, end))

    regions = []
    for turn, _, speaker in annotation.itertracks(yield_label=True):
        if turn.end <= turn.start:
            continue
        has_overlap = any(
            min(float(turn.end), overlap_end) - max(float(turn.start), overlap_start) >= 0.08
            for overlap_start, overlap_end in overlap_intervals
        )
        regions.append({
            "start": round(float(turn.start), 3),
            "end": round(float(turn.end), 3),
            "speaker_id": str(speaker),
            "confidence": 0.90,
            "model": model,
            "fallback": False,
            "overlap": has_overlap,
        })

    if not regions:
        raise RuntimeError("Pyannote returned no speaker regions.")
    with open(args.output, "w", encoding="utf-8") as output_file:
        json.dump({
            "regions": regions,
            "overlaps": [
                {"start": round(start, 3), "end": round(end, 3)}
                for start, end in overlap_intervals
            ],
        }, output_file, indent=2)
    return 0


TTS_READY_PREFIX = "DUBFORGE_TTS_READY\t"
TTS_RESULT_PREFIX = "DUBFORGE_TTS_RESULT\t"


def _render_tts(model, args: argparse.Namespace) -> dict:
    import wave

    import numpy as np

    # generate() dispatches on the checkpoint's own config.tts_model_type
    # (base / custom_voice / voice_design) and forwards lang_code onward as
    # `language` to the variant-specific helpers, so there is nothing to route by
    # hand. Letting it decide also keeps a local weights directory working, whose
    # folder name may say nothing about which variant it holds.
    call_kwargs = {
        "text": args.text,
        "lang_code": args.language or "auto",
        "max_tokens": max(8, int(args.max_tokens)),
    }
    if args.ref_audio:
        # Cloning: the reference clip defines the voice, so neither a preset name
        # nor a style instruction is sent alongside it.
        call_kwargs["ref_audio"] = args.ref_audio
        call_kwargs["ref_text"] = args.ref_text
    else:
        if args.voice:
            call_kwargs["voice"] = args.voice
        if args.instruct:
            # Used by CustomVoice and VoiceDesign; ignored by base checkpoints.
            call_kwargs["instruct"] = args.instruct

    chunks = []
    sample_rate = 0
    for result in model.generate(**call_kwargs):
        audio = getattr(result, "audio", None)
        if audio is None:
            continue
        try:
            samples = np.asarray(audio, dtype=np.float32).reshape(-1)
        except (TypeError, ValueError):
            import mlx.core as mx

            samples = np.asarray(audio.astype(mx.float32), dtype=np.float32).reshape(-1)
        if samples.size:
            chunks.append(samples)
        sample_rate = sample_rate or int(getattr(result, "sample_rate", 0) or 0)

    if not chunks:
        raise RuntimeError("Qwen3-TTS produced no audio for this segment.")

    waveform = np.concatenate(chunks)
    sample_rate = sample_rate or args.sample_rate

    # Only rescale when the decoder actually clipped. Peak-normalising every
    # segment would flatten the loudness differences between them and fight the
    # loudness pass that runs during mixing.
    peak = float(np.max(np.abs(waveform)))
    if peak > 1.0:
        waveform = waveform / peak
    pcm = (np.clip(waveform, -1.0, 1.0) * 32767.0).astype("<i2")

    with wave.open(args.output, "wb") as output_file:
        output_file.setnchannels(1)
        output_file.setsampwidth(2)
        output_file.setframerate(sample_rate)
        output_file.writeframes(pcm.tobytes())

    return {
        "sample_rate": sample_rate,
        "samples": int(pcm.size),
        "duration": round(pcm.size / float(sample_rate), 3),
    }


def _load_tts_model(model_reference: str):
    from pathlib import Path

    model_str = str(model_reference or "").strip()
    if os.path.exists(model_str):
        os.environ["HF_HUB_OFFLINE"] = "1"
    else:
        hub_cache = Path.home() / ".cache" / "huggingface" / "hub"
        hf_cache_dir = os.environ.get("HF_HUB_CACHE") or os.environ.get("HF_HOME")
        if hf_cache_dir:
            hub_cache = Path(os.path.expanduser(hf_cache_dir))
        cached = hub_cache / f"models--{model_str.replace('/', '--')}"
        if cached.is_dir():
            os.environ["HF_HUB_OFFLINE"] = "1"

    from mlx_audio.tts.utils import load_model

    return load_model(model_reference)


def run_tts(args: argparse.Namespace) -> int:
    model = _load_tts_model(args.model)
    print(json.dumps(_render_tts(model, args)))
    return 0


def run_tts_server(args: argparse.Namespace) -> int:
    """Keeps Qwen weights and clone-reference caches warm across segments."""
    model = _load_tts_model(args.model)
    print(f"{TTS_READY_PREFIX}{json.dumps({'model': args.model})}", flush=True)

    for line in sys.stdin:
        if not line.strip():
            continue
        try:
            payload = json.loads(line)
            request = SimpleNamespace(
                text=str(payload.get("text") or ""),
                output=str(payload.get("output") or ""),
                language=str(payload.get("language") or ""),
                voice=str(payload.get("voice") or ""),
                instruct=str(payload.get("instruct") or ""),
                ref_audio=str(payload.get("ref_audio") or ""),
                ref_text=str(payload.get("ref_text") or ""),
                sample_rate=int(payload.get("sample_rate") or 24000),
                max_tokens=int(payload.get("max_tokens") or 1200),
            )
            if not request.text or not request.output:
                raise ValueError("TTS request requires text and output paths.")
            result = _render_tts(model, request)
            response = {"ok": True, **result}
        except Exception as error:
            response = {"ok": False, "error": str(error)}
        print(f"{TTS_RESULT_PREFIX}{json.dumps(response)}", flush=True)

    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    diarize = subparsers.add_parser("diarize")
    diarize.add_argument("--audio", required=True)
    diarize.add_argument("--output", required=True)
    diarize.add_argument("--model", required=True)
    diarize.add_argument("--device", choices=("cpu", "mps", "cuda"), default="cpu")
    diarize.add_argument("--num-speakers", type=int)
    diarize.set_defaults(handler=run_diarization)

    transcribe = subparsers.add_parser("transcribe")
    transcribe.add_argument("--audio", required=True)
    transcribe.add_argument("--output", required=True)
    transcribe.add_argument("--model", required=True)
    transcribe.add_argument("--compute-type", choices=("int8", "float16", "float32"), default="int8")
    transcribe.add_argument("--cpu-threads", type=int, default=4)
    transcribe.add_argument("--language")
    transcribe.set_defaults(handler=run_transcription)

    tts = subparsers.add_parser("tts")
    tts.add_argument("--text", required=True)
    tts.add_argument("--output", required=True)
    tts.add_argument("--model", required=True)
    tts.add_argument("--voice", default="")
    tts.add_argument("--language", default="")
    tts.add_argument("--instruct", default="")
    tts.add_argument("--ref-audio", dest="ref_audio", default="")
    tts.add_argument("--ref-text", dest="ref_text", default="")
    tts.add_argument("--max-tokens", dest="max_tokens", type=int, default=1200)
    # Used only when neither the result nor the model reports a rate. Qwen3-TTS
    # decodes to 24 kHz; the "12Hz" in the checkpoint name is the codec token
    # rate, not the audio sample rate.
    tts.add_argument("--sample-rate", dest="sample_rate", type=int, default=24000)
    tts.set_defaults(handler=run_tts)

    tts_server = subparsers.add_parser("tts-server")
    tts_server.add_argument("--model", required=True)
    tts_server.set_defaults(handler=run_tts_server)

    args = parser.parse_args()
    try:
        return args.handler(args)
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
