"""Small readers for the FromSoftware formats used here: DCX, BND4, TPF, CCM and FMG."""
import io
import struct
import zlib

from PIL import Image


def undcx(data):
    """Decompresses a DCX (DFLT/zlib) container; other data is returned as is."""
    if data[:4] != b"DCX\0":
        return data
    kind = data[0x28:0x2C]
    if kind != b"DFLT":
        raise ValueError(f"unsupported DCX compression {kind!r}")
    i = data.index(b"DCA\0")
    start = i + struct.unpack_from(">i", data, i + 4)[0]
    return zlib.decompress(data[start:])


def _reverse_bits(x):
    return int(f"{x:08b}"[::-1], 2)


def bnd4(data):
    """Lists the files in a BND4 binder as (name, bytes) pairs."""
    if data[:4] not in (b"BND4", b"BHF4"):
        raise ValueError("not a BND4 binder")
    count = struct.unpack_from("<i", data, 0x0C)[0]
    header_size = struct.unpack_from("<q", data, 0x20)[0]
    unicode, fmt = data[0x30], data[0x31]
    if data[0x0A]:
        fmt = _reverse_bits(fmt)
    out = []
    p = 0x40
    for _ in range(count):
        q = p + 8
        size = struct.unpack_from("<q", data, q)[0]
        q += 8
        if fmt & 0x20:
            q += 8  # uncompressed size
        if fmt & 0x10:
            offset = struct.unpack_from("<q", data, q)[0]
            q += 8
        else:
            offset = struct.unpack_from("<I", data, q)[0]
            q += 4
        if fmt & 0x02:
            q += 4  # id
        name = None
        if fmt & 0x0C:
            noff = struct.unpack_from("<i", data, q)[0]
            if unicode:
                end = noff
                while data[end:end + 2] != b"\0\0":
                    end += 2
                name = data[noff:end].decode("utf-16le")
            else:
                name = data[noff:data.index(b"\0", noff)].decode("shift_jis", "replace")
        out.append((name.replace("\\", "/").split("/")[-1] if name else None, data[offset:offset + size]))
        p += header_size
    return out


def bnd4_names(data):
    return [n for n, _ in bnd4(data)]


def tpf(data):
    """Lists the textures in a TPF as (name, PIL image) pairs."""
    if data[:4] != b"TPF\0":
        raise ValueError("not a TPF")
    count = struct.unpack_from("<i", data, 8)[0]
    utf16 = data[14] == 1
    out = []
    for i in range(count):
        off, size, _fmt, _typ, _mips, _f1, noff, _f2 = struct.unpack_from("<IiBBBBiI", data, 16 + 20 * i)
        if utf16:
            end = noff
            while data[end:end + 2] != b"\0\0":
                end += 2
            name = data[noff:end].decode("utf-16le")
        else:
            name = data[noff:data.index(b"\0", noff)].decode("shift_jis", "replace")
        img = Image.open(io.BytesIO(undcx(data[off:off + size])))
        img.load()
        out.append((name, img.convert("RGBA")))
    return out


def tpf_names(data):
    count = struct.unpack_from("<i", data, 8)[0]
    utf16 = data[14] == 1
    names = []
    for i in range(count):
        noff = struct.unpack_from("<i", data, 16 + 20 * i + 12)[0]
        if utf16:
            end = noff
            while data[end:end + 2] != b"\0\0":
                end += 2
            names.append(data[noff:end].decode("utf-16le"))
        else:
            names.append(data[noff:data.index(b"\0", noff)].decode("shift_jis", "replace"))
    return names


def ccm(data):
    """Bitmap font metrics (DS2 CCM v2): line height and per-character glyph boxes."""
    _ver, _size, height, tex_w, tex_h, nreg, nglyph, _, regoff, glyoff = struct.unpack_from("<iihhhhhhii", data, 0)
    regions = [struct.unpack_from("<hhhh", data, regoff + 8 * i) for i in range(nreg)]
    glyphs = {}
    for i in range(nglyph):
        code, roff, tex, pre, width, adv, _, _ = struct.unpack_from("<iihhhhii", data, glyoff + 24 * i)
        glyphs[code] = {"box": regions[(roff - regoff) // 8], "page": tex, "pre": pre, "width": width, "advance": adv}
    return {"height": height, "page_size": [tex_w, tex_h], "glyphs": glyphs}


def fmg(data):
    """Text table (FMG v1) as {id: text}."""
    if data[:4] != b"\0\0\1\0":
        raise ValueError("not an FMG v1 text table")
    ngroups, nstrings, soff = struct.unpack_from("<iii", data, 0x0C)
    offsets = struct.unpack_from(f"<{nstrings}i", data, soff)
    out = {}
    for g in range(ngroups):
        idx, first, last = struct.unpack_from("<iii", data, 0x1C + 12 * g)
        for k, sid in enumerate(range(first, last + 1)):
            o = offsets[idx + k]
            if o == 0:
                continue
            end = o
            while data[end:end + 2] != b"\0\0":
                end += 2
            out[sid] = data[o:end].decode("utf-16le")
    return out
