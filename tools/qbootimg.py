#!/usr/bin/env python3
"""Unpack a Qualcomm-style Android boot image (header v0 + dt_size)."""
import struct, sys, os

def cstr(b):
    return b.split(b'\x00', 1)[0].decode('utf-8', 'replace')

def main(path, outdir):
    os.makedirs(outdir, exist_ok=True)
    with open(path, 'rb') as f:
        hdr = f.read(1648)
    assert hdr[:8] == b'ANDROID!', 'not a boot image'
    (kernel_size, kernel_addr, ramdisk_size, ramdisk_addr,
     second_size, second_addr, tags_addr, page_size,
     dt_size, os_version) = struct.unpack('<10I', hdr[8:48])
    name = cstr(hdr[48:64])
    cmdline = cstr(hdr[64:576])
    extra = cstr(hdr[608:1632])

    print(f'page_size      : {page_size}')
    print(f'kernel_size    : {kernel_size}')
    print(f'kernel_addr    : 0x{kernel_addr:08x}')
    print(f'ramdisk_size   : {ramdisk_size}')
    print(f'ramdisk_addr   : 0x{ramdisk_addr:08x}')
    print(f'second_size    : {second_size}')
    print(f'tags_addr      : 0x{tags_addr:08x}')
    print(f'dt_size        : {dt_size}')
    print(f'os_version raw : 0x{os_version:08x}')
    print(f'board name     : {name!r}')
    print(f'cmdline        : {cmdline}')
    if extra:
        print(f'extra_cmdline  : {extra}')
    # base = kernel_addr - 0x00008000 conventionally
    print(f'base (derived) : 0x{kernel_addr - 0x8000:08x}')
    print(f'kernel_offset  : 0x{0x8000:08x}')
    print(f'ramdisk_offset : 0x{ramdisk_addr - (kernel_addr - 0x8000):08x}')
    print(f'tags_offset    : 0x{tags_addr - (kernel_addr - 0x8000):08x}')

    def pages(n):
        return (n + page_size - 1) // page_size

    off = page_size
    with open(path, 'rb') as f:
        for label, size in (('kernel', kernel_size), ('ramdisk', ramdisk_size),
                            ('second', second_size), ('dt', dt_size)):
            if size == 0:
                continue
            f.seek(off)
            data = f.read(size)
            out = os.path.join(outdir, label + '.img')
            with open(out, 'wb') as o:
                o.write(data)
            print(f'wrote {out} ({size} bytes)')
            off += pages(size) * page_size

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
