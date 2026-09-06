import ipaddress
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import uuid
from pathlib import Path
from urllib.parse import urlparse

from processing.config import API_SETTINGS, UPLOADS_DIR
from processing.services.ffmpeg_service import FFmpegService


class MediaURLService:
    """Inspects and acquires public, non-DRM media URLs with yt-dlp."""

    MAX_DURATION_SECONDS = 12 * 60 * 60
    MAX_FILE_SIZE_BYTES = 20 * 1024 * 1024 * 1024

    @classmethod
    def validate_url(cls, value: str) -> str:
        url = (value or "").strip()
        parsed = urlparse(url)
        if parsed.scheme not in {"http", "https"}:
            raise ValueError("Only HTTP and HTTPS video links are supported.")
        if not parsed.hostname or parsed.username or parsed.password:
            raise ValueError("Enter a valid public video link without embedded credentials.")

        try:
            addresses = {
                item[4][0]
                for item in socket.getaddrinfo(parsed.hostname, parsed.port or 443, type=socket.SOCK_STREAM)
            }
        except socket.gaierror as exc:
            raise ValueError("The video host could not be resolved.") from exc

        if not addresses:
            raise ValueError("The video host could not be resolved.")
        for address in addresses:
            ip = ipaddress.ip_address(address)
            if not ip.is_global:
                raise ValueError("Local and private network video links are not allowed.")
        return url

    @staticmethod
    def _yt_dlp_command() -> list[str]:
        configured = os.path.expanduser(str(API_SETTINGS.get("ytDlpPath", "")).strip())
        if configured and os.path.isfile(configured) and os.access(configured, os.X_OK):
            return [configured]

        try:
            __import__("yt_dlp")
            return [sys.executable, "-m", "yt_dlp"]
        except ImportError:
            pass

        candidates = [shutil.which("yt-dlp"), "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
        for candidate in candidates:
            if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return [candidate]
        raise RuntimeError("yt-dlp is not installed. Install it before importing video links.")

    @staticmethod
    def _clean_error(message: str, source_url: str) -> str:
        text = (message or "Media import failed.").replace(source_url, "the supplied link")
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        if not lines:
            return "Media import failed."
        error_lines = [line for line in lines if "ERROR:" in line]
        return (error_lines[-1] if error_lines else lines[-1])[:800]

    @classmethod
    def inspect(cls, source_url: str) -> dict:
        url = cls.validate_url(source_url)
        command = cls._yt_dlp_command() + [
            "--dump-single-json",
            "--skip-download",
            "--no-playlist",
            "--no-warnings",
            "--socket-timeout", "20",
            url,
        ]
        try:
            completed = subprocess.run(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
            )
        except subprocess.TimeoutExpired as exc:
            raise RuntimeError("The video host did not respond in time.") from exc

        if completed.returncode != 0:
            raise RuntimeError(cls._clean_error(completed.stderr, url))

        try:
            info = json.loads(completed.stdout)
        except json.JSONDecodeError as exc:
            raise RuntimeError("The video host returned invalid media information.") from exc

        if info.get("_type") in {"playlist", "multi_video"}:
            raise ValueError("Playlist imports are not supported. Open one video and paste its link.")
        if info.get("is_live") or info.get("live_status") in {"is_live", "is_upcoming"}:
            raise ValueError("Live and upcoming streams cannot be imported.")
        if info.get("vcodec") == "none":
            raise ValueError("The supplied link does not contain a video stream.")

        duration = float(info.get("duration") or 0.0)
        if duration > cls.MAX_DURATION_SECONDS:
            raise ValueError("Videos longer than 12 hours cannot be imported.")

        subtitles = sorted(set((info.get("subtitles") or {}).keys()) | set((info.get("automatic_captions") or {}).keys()))
        width = info.get("width")
        height = info.get("height")
        resolution = f"{width} x {height}" if width and height else (info.get("resolution") or "Unknown")
        file_size = info.get("filesize") or info.get("filesize_approx")

        return {
            "title": info.get("title") or "Untitled video",
            "creator": info.get("uploader") or info.get("channel") or info.get("creator") or "Unknown creator",
            "duration": duration,
            "thumbnail": info.get("thumbnail"),
            "platform": info.get("extractor_key") or info.get("extractor") or "Web",
            "resolution": resolution,
            "fileSize": file_size,
            "extension": info.get("ext") or "",
            "subtitles": subtitles[:50],
            "mediaId": str(info.get("id") or ""),
        }

    @classmethod
    def download(
        cls,
        source_url: str,
        progress_callback,
        cancelled_callback,
        process_callback,
    ) -> dict:
        url = cls.validate_url(source_url)
        metadata = cls.inspect(url)
        if cancelled_callback():
            raise InterruptedError("Download cancelled by user.")

        stem = f"url_{uuid.uuid4().hex}"
        output_template = str(UPLOADS_DIR / f"{stem}.%(ext)s")
        ffmpeg = FFmpegService.get_ffmpeg_binary()
        command = cls._yt_dlp_command() + [
            "--no-playlist",
            "--newline",
            "--no-warnings",
            "--socket-timeout", "30",
            "--max-filesize", str(cls.MAX_FILE_SIZE_BYTES),
            "--concurrent-fragments", "4",
            "--ffmpeg-location", ffmpeg,
            "--format", "bv*[vcodec^=avc1]+ba[acodec^=mp4a]/b[ext=mp4]/bv*+ba/b",
            "--merge-output-format", "mp4",
            "--output", output_template,
            "--progress-template", "download:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
            "--print", "after_move:__DUBFORGE_FILE__:%(filepath)s",
            url,
        ]

        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        process_callback(process)
        downloaded_path = None
        recent_output = []
        try:
            assert process.stdout is not None
            for raw_line in process.stdout:
                line = raw_line.strip()
                if not line:
                    continue
                recent_output.append(line)
                recent_output = recent_output[-20:]
                if cancelled_callback():
                    process.terminate()
                    raise InterruptedError("Download cancelled by user.")
                if line.startswith("download:"):
                    parts = line[len("download:"):].split("|")
                    match = re.search(r"([0-9]+(?:\.[0-9]+)?)", parts[0])
                    percent = float(match.group(1)) if match else 0.0
                    speed = parts[1].strip() if len(parts) > 1 else ""
                    eta = parts[2].strip() if len(parts) > 2 else ""
                    detail = "Downloading video"
                    if speed and speed != "NA":
                        detail += f" at {speed}"
                    if eta and eta != "NA":
                        detail += f" - {eta} remaining"
                    progress_callback(min(90.0, max(2.0, percent * 0.88 + 2.0)), detail)
                elif line.startswith("__DUBFORGE_FILE__:"):
                    downloaded_path = line.split(":", 1)[1].strip()
            return_code = process.wait()
        except InterruptedError:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            for partial in UPLOADS_DIR.glob(f"{stem}.*"):
                partial.unlink(missing_ok=True)
            raise
        finally:
            process_callback(None)

        if cancelled_callback():
            raise InterruptedError("Download cancelled by user.")
        if return_code != 0:
            raise RuntimeError(cls._clean_error("\n".join(recent_output), url))

        if not downloaded_path or not os.path.exists(downloaded_path):
            candidates = sorted(
                path for path in UPLOADS_DIR.glob(f"{stem}.*")
                if path.suffix not in {".part", ".ytdl", ".json"}
            )
            downloaded_path = str(candidates[0]) if candidates else ""
        if not downloaded_path or not os.path.exists(downloaded_path):
            raise RuntimeError("The download completed but no video file was produced.")

        progress_callback(92.0, "Validating downloaded media")
        normalized_path = cls._normalize_media(Path(downloaded_path), stem)
        progress_callback(100.0, "Video link imported")
        return {
            "path": str(normalized_path),
            "metadata": metadata,
        }

    @classmethod
    def _normalize_media(cls, source_path: Path, stem: str) -> Path:
        ffmpeg = FFmpegService.get_ffmpeg_binary()
        ffprobe = shutil.which("ffprobe") or str(Path(ffmpeg).with_name("ffprobe"))
        probe = subprocess.run(
            [ffprobe, "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name", "-of", "json", str(source_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        if probe.returncode != 0:
            source_path.unlink(missing_ok=True)
            raise RuntimeError("The downloaded file does not contain a readable video stream.")

        try:
            streams = json.loads(probe.stdout).get("streams", [])
            video_codec = streams[0].get("codec_name", "") if streams else ""
        except (json.JSONDecodeError, IndexError):
            video_codec = ""
        if not video_codec:
            source_path.unlink(missing_ok=True)
            raise RuntimeError("The downloaded file does not contain a video stream.")

        audio_probe = subprocess.run(
            [ffprobe, "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name", "-of", "json", str(source_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        try:
            has_audio = bool(json.loads(audio_probe.stdout).get("streams", []))
        except json.JSONDecodeError:
            has_audio = False

        if not has_audio:
            audio_candidates = []
            for candidate in UPLOADS_DIR.glob(f"{stem}.*"):
                if candidate == source_path or candidate.suffix in {".part", ".ytdl", ".json"}:
                    continue
                candidate_probe = subprocess.run(
                    [ffprobe, "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=codec_name", "-of", "json", str(candidate)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=30,
                )
                try:
                    if json.loads(candidate_probe.stdout).get("streams", []):
                        audio_candidates.append(candidate)
                except json.JSONDecodeError:
                    continue
            if not audio_candidates:
                for partial in UPLOADS_DIR.glob(f"{stem}.*"):
                    partial.unlink(missing_ok=True)
                raise RuntimeError("The downloaded video does not contain an audio stream.")

            muxed_path = UPLOADS_DIR / f"{stem}.muxed.mp4"
            muxed = subprocess.run(
                [
                    ffmpeg, "-y", "-i", str(source_path), "-i", str(audio_candidates[0]),
                    "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy",
                    "-c:a", "aac", "-b:a", "256k", "-shortest", "-movflags", "+faststart",
                    str(muxed_path),
                ],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=6 * 60 * 60,
            )
            if muxed.returncode != 0 or not muxed_path.exists():
                muxed_path.unlink(missing_ok=True)
                raise RuntimeError("The downloaded video and audio streams could not be merged.")
            source_path.unlink(missing_ok=True)
            source_path = muxed_path

        destination = UPLOADS_DIR / f"{stem}.mp4"
        if source_path.suffix.lower() == ".mp4" and video_codec in {"h264", "hevc"}:
            if source_path != destination:
                source_path.replace(destination)
            for component in UPLOADS_DIR.glob(f"{stem}.*"):
                if component != destination:
                    component.unlink(missing_ok=True)
            return destination

        command = [
            ffmpeg, "-y", "-i", str(source_path),
            "-map", "0:v:0", "-map", "0:a:0?",
            "-c:v", "libx264", "-preset", "fast", "-crf", "18",
            "-c:a", "aac", "-b:a", "256k",
            "-movflags", "+faststart", str(destination),
        ]
        converted = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=6 * 60 * 60,
        )
        if converted.returncode != 0 or not destination.exists():
            destination.unlink(missing_ok=True)
            raise RuntimeError("The downloaded video could not be normalized to MP4.")
        source_path.unlink(missing_ok=True)
        for component in UPLOADS_DIR.glob(f"{stem}.*"):
            if component != destination:
                component.unlink(missing_ok=True)
        return destination
