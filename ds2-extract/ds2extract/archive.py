"""Reads files out of Dark Souls II: Scholar of the First Sin's packed data.

The game keeps its menus, fonts and texts in GameDataEbl.bdt. The index next to
it (GameDataEbl.bhd) is RSA-encrypted with the public key the game ships in
GameDataKeyCode.pem, and some files inside the .bdt are AES-encrypted with keys
stored in that index. Nothing here touches the game files; they are only read.
"""
import base64
import struct
from pathlib import Path

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes


def _read_pem_rsa_public_key(path):
    """Returns (n, e) from a PKCS#1 "RSA PUBLIC KEY" PEM file."""
    lines = Path(path).read_text().splitlines()
    der = base64.b64decode("".join(l for l in lines if not l.startswith("-----")))

    def length(i):
        n = der[i]
        i += 1
        if n & 0x80:
            k = n & 0x7F
            n = int.from_bytes(der[i:i + k], "big")
            i += k
        return n, i

    assert der[0] == 0x30, "not a DER sequence"
    _, i = length(1)
    ints = []
    while i < len(der):
        assert der[i] == 0x02, "expected an INTEGER"
        n, i = length(i + 1)
        ints.append(int.from_bytes(der[i:i + n], "big"))
        i += n
    return ints[0], ints[1]


def _rsa_decrypt_blocks(data, n, e):
    """Raw RSA with the public key, 256-byte blocks in, 255-byte blocks out."""
    out = bytearray()
    for i in range(0, len(data), 256):
        c = int.from_bytes(data[i:i + 256], "big")
        out += pow(c, e, n).to_bytes(255, "big")
    return bytes(out)


def name_hash(path):
    """FromSoftware's 32-bit file name hash (used by the .bhd index)."""
    h = 0
    for c in "/" + path.strip().replace("\\", "/").lower().lstrip("/"):
        h = (h * 37 + ord(c)) & 0xFFFFFFFF
    return h


class Record:
    __slots__ = ("hash", "size", "offset", "aes_key", "aes_ranges")

    def __init__(self, h, size, offset, aes_key, aes_ranges):
        self.hash, self.size, self.offset = h, size, offset
        self.aes_key, self.aes_ranges = aes_key, aes_ranges


class GameArchive:
    def __init__(self, game_dir, name="GameDataEbl"):
        game_dir = Path(game_dir)
        n, e = _read_pem_rsa_public_key(game_dir / f"{name[:-3]}KeyCode.pem")
        bhd = _rsa_decrypt_blocks((game_dir / f"{name}.bhd").read_bytes(), n, e)
        if bhd[:4] != b"BHD5":
            raise ValueError(f"{name}.bhd did not decrypt to a BHD5 index")
        self.records = {}
        bucket_count, buckets_offset = struct.unpack_from("<ii", bhd, 0x10)
        for b in range(bucket_count):
            count, offset = struct.unpack_from("<ii", bhd, buckets_offset + 8 * b)
            for k in range(count):
                h, size, off, _sha, aes = struct.unpack_from("<IiqQQ", bhd, offset + 32 * k)
                key, ranges = None, []
                if aes:
                    key = bhd[aes:aes + 16]
                    rc = struct.unpack_from("<i", bhd, aes + 16)[0]
                    ranges = [struct.unpack_from("<qq", bhd, aes + 20 + 16 * j) for j in range(rc)]
                self.records[h] = Record(h, size, off, key, ranges)
        self._bdt = open(game_dir / f"{name}.bdt", "rb")

    def read(self, rec, limit=None):
        """The decrypted bytes of one file (or only its first `limit` bytes)."""
        if isinstance(rec, int):
            rec = self.records[rec]
        size = rec.size if limit is None else min(rec.size, limit)
        self._bdt.seek(rec.offset)
        data = bytearray(self._bdt.read(size))
        if rec.aes_key:
            for start, end in rec.aes_ranges:
                if start == -1 or end <= start or start >= len(data):
                    continue
                end = min(end, start + (len(data) - start) // 16 * 16)
                dec = Cipher(algorithms.AES(rec.aes_key), modes.ECB()).decryptor()
                data[start:end] = dec.update(bytes(data[start:end])) + dec.finalize()
        return bytes(data)

    def __iter__(self):
        return iter(self.records.values())
