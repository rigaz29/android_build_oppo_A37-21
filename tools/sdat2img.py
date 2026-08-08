#!/usr/bin/env python3
"""Minimal sdat2img: rebuild a raw ext4 image from transfer.list + .new.dat."""
import sys

BLOCK = 4096

def parse_ranges(text):
    n = list(map(int, text.split(',')))
    count = n[0]
    vals = n[1:]
    assert len(vals) == count and count % 2 == 0
    return [(vals[i], vals[i + 1]) for i in range(0, count, 2)]

def main(tlist, dat, out):
    with open(tlist) as f:
        lines = [l.strip() for l in f if l.strip()]
    version = int(lines[0])
    total_blocks = int(lines[1])
    print(f'transfer list version {version}, total blocks {total_blocks}')
    cmds = []
    for line in lines[2:]:
        parts = line.split(' ', 1)
        if parts[0] == 'new':
            cmds.append(parse_ranges(parts[1]))
    # `total_blocks` counts data blocks only; the image must span the highest
    # block index any range touches, with the gaps left as holes.
    image_blocks = max(end for ranges in cmds for _, end in ranges)
    src = open(dat, 'rb')
    outf = open(out, 'wb')
    outf.truncate(image_blocks * BLOCK)
    written = 0
    for ranges in cmds:
        for begin, end in ranges:
            outf.seek(begin * BLOCK)
            remaining = (end - begin) * BLOCK
            while remaining:
                chunk = src.read(min(remaining, 1 << 22))
                if not chunk:
                    raise SystemExit('unexpected EOF in .dat')
                outf.write(chunk)
                remaining -= len(chunk)
                written += len(chunk)
    outf.close()
    src.close()
    print(f'wrote {out}: {written} bytes of data, image {image_blocks * BLOCK} bytes')

if __name__ == '__main__':
    main(*sys.argv[1:4])
