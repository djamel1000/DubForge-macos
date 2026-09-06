import re
from datetime import datetime

class SubtitleParser:
    @staticmethod
    def parse_timecode(time_str: str) -> float:
        """Converts timecodes like 00:00:01,000 or 00:00:01.000 or 01:37 to seconds."""
        time_str = time_str.strip().replace(',', '.')
        parts = time_str.split(':')
        if len(parts) == 2:  # MM:SS
            m, s = parts
            h = 0
        elif len(parts) == 3:  # HH:MM:SS
            h, m, s = parts
        else:
            return float(time_str)
        
        seconds = float(h) * 3600 + float(m) * 60 + float(s)
        return round(seconds, 3)

    @classmethod
    def parse_srt(cls, file_content: str) -> list:
        """Parses standard SRT subtitle formats."""
        segments = []
        # Normalizes line endings
        content = file_content.replace('\r\n', '\n')
        # Splitting by double newline
        blocks = re.split(r'\n\n+', content)
        
        segment_id = 1
        for block in blocks:
            lines = [l.strip() for l in block.split('\n') if l.strip()]
            if len(lines) >= 3:
                # Line 0 is ID (sometimes not numeric if dirty, so we skip or re-index)
                # Line 1 is timing: 00:00:01,000 --> 00:00:03,500
                timing_match = re.match(r'(\d+:\d+:\d+[\.,]\d+)\s*-->\s*(\d+:\d+:\d+[\.,]\d+)', lines[1])
                if timing_match:
                    start_sec = cls.parse_timecode(timing_match.group(1))
                    end_sec = cls.parse_timecode(timing_match.group(2))
                    text = " ".join(lines[2:])
                    segments.append({
                        "id": segment_id,
                        "start": start_sec,
                        "end": end_sec,
                        "duration": round(end_sec - start_sec, 3),
                        "source_text": text
                    })
                    segment_id += 1
        return segments

    @classmethod
    def parse_timestamped_txt(cls, file_content: str) -> list:
        """Parses TXT format: [00:01:37] Who built this canopy?"""
        segments = []
        lines = [l.strip() for l in file_content.split('\n') if l.strip()]
        
        parsed_lines = []
        # Regex to match [HH:MM:SS] or [MM:SS] or simply [SS]
        pattern = r'^\[(\d+:?\d*:?\d*[\.,]?\d*)\]\s*(.*)$'
        
        for line in lines:
            match = re.match(pattern, line)
            if match:
                timecode_str = match.group(1)
                text = match.group(2).strip()
                start_sec = cls.parse_timecode(timecode_str)
                parsed_lines.append((start_sec, text))
                
        # If only start timestamps exist, infer end time from the next line's start
        for i, (start_sec, text) in enumerate(parsed_lines):
            if i < len(parsed_lines) - 1:
                end_sec = parsed_lines[i + 1][0]
            else:
                # For the final line, default duration is 5.0 seconds
                end_sec = start_sec + 5.0
                
            segments.append({
                "id": i + 1,
                "start": start_sec,
                "end": end_sec,
                "duration": round(end_sec - start_sec, 3),
                "source_text": text
            })
            
        return segments

    @classmethod
    def parse(cls, filepath: str) -> list:
        """Router to select parser based on file extension."""
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        if filepath.endswith('.srt'):
            return cls.parse_srt(content)
        elif filepath.endswith('.vtt'):
            # Convert simple VTT to SRT-like for simplicity
            vtt_content = re.sub(r'^WEBVTT.*\n', '', content)
            return cls.parse_srt(vtt_content)
        else:
            # Fallback to timestamped TXT
            return cls.parse_timestamped_txt(content)
