"""Export the approved field recordings; requires the retained local auditions and FFmpeg."""

import array
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / 'audio-experiments/outdoor-ambience-recordings-v1'
OUTPUT = ROOT / 'public/audio/ambience'


def main():
    original = json.loads((SOURCES / 'sources.json').read_text())['clips']
    choices = json.loads((SOURCES / 'plains-choices-v2/sources.json').read_text())['clips']
    prairie = next(clip for clip in choices if clip['id'] == 'c-oklahoma-prairie')
    clips = [(name, clip, SOURCES / f'{name}-source.mp3', clip['audition']['startSeconds'])
             for clip in original if (name := clip['environment']) != 'plains']
    clips.insert(0, ('plains', prairie, SOURCES / 'plains-choices-v2/c-oklahoma-prairie-source.mp3', 30))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = []
    filters = 'highpass=f=45,loudnorm=I=-24:TP=-3:LRA=11,aresample=48000'
    sample_rate = 48000
    channels = 2
    overlap_samples = sample_rate * channels
    source_samples = 21 * overlap_samples
    for name, clip, source, start in clips:
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        if source_hash != clip['sourceSha256']:
            raise ValueError(f'Approved source hash changed: {source}')
        target = OUTPUT / f'{name}.ogg'
        # Mix the tail over the head in PCM so the join has an exact sample
        # count. Timestamp rounding in a filter graph can drop edge samples.
        pcm = subprocess.check_output(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error',
                                       '-ss', str(start), '-i', str(source), '-t', '21', '-af', filters,
                                       '-ac', '2', '-ar', '48000', '-f', 'f32le', '-'])
        samples = array.array('f', pcm)
        if sys.byteorder != 'little':
            samples.byteswap()
        if len(samples) < source_samples - 2048:
            raise ValueError(f'Source excerpt was truncated: {source}')
        samples.extend([0.0] * max(0, source_samples - len(samples)))
        body_end = 20 * overlap_samples
        loop = samples[overlap_samples:body_end]
        for index in range(overlap_samples):
            blend = (index // channels) / (sample_rate - 1)
            loop.append(samples[body_end + index] * (1 - blend) + samples[index] * blend)
        if sys.byteorder != 'little':
            loop.byteswap()
        subprocess.run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y',
                        '-f', 'f32le', '-ar', '48000', '-ac', '2', '-i', '-',
                        '-c:a', 'libvorbis', '-q:a', '5',
                        '-metadata', f'artist={clip["author"]}', '-metadata', f'title={clip["title"]}',
                        '-metadata', f'comment={clip["page"]}', '-metadata', 'license=CC0 1.0',
                        str(target)], input=loop.tobytes(), check=True)
        manifest.append({'environment': name, 'file': target.name, 'title': clip['title'],
                         'author': clip['author'], 'sourcePage': clip['page'], 'sourceAudio': clip['audio'],
                         'license': 'CC0 1.0', 'licenseUrl': 'https://creativecommons.org/publicdomain/zero/1.0/',
                         'sourceSha256': source_hash, 'sourceStartSeconds': start, 'sourceDurationSeconds': 21,
                         'loopDurationSeconds': 20, 'crossfadeSeconds': 1, 'processing': filters + '; linear PCM tail/head overlap',
                         'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
        print(target.relative_to(ROOT), flush=True)
    (OUTPUT / 'sources.json').write_text(json.dumps({'clips': manifest}, indent=2) + '\n')


if __name__ == '__main__':
    main()
