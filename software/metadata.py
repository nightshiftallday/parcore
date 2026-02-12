from dataclasses import dataclass
from enum import Enum
from struct import pack, unpack, calcsize

class Encoding(Enum):
    PLAIN = 0
    HYBRID = 1

    def __str__(self):
        return f'{self.name}'

class Compression(Enum):
    RAW = 0
    SNAPPY = 1
    
    def __str__(self):
        return f'{self.name}'

class Type(Enum):
    BYTE = 0
    INT32 = 1
    INT64 = 2
    FLOAT = 3
    DOUBLE = 4

    def __str__(self):
        return f'{self.name}'

def _read_exact(f, n: int) -> bytes:
    b = f.read(n)
    if len(b) != n:
        raise Exception(f"attempted to read {n} bytes, only got {len(b)}")
    return b

@dataclass
class String:
    value: str

    def to_file(self, f):
        raw = self.value.encode()
        f.write(pack("<I", len(raw)))
        f.write(raw)

    @classmethod
    def from_file(cls, f):
        (n,) = unpack("<I", _read_exact(f, 4))
        raw = _read_exact(f, n)
        return cls(raw.decode())

@dataclass
class Page:
    encoding: Encoding
    offset: int
    size: int
    num_values: int

    _fmt = "<BQQQ"  # encoding, offset, size, num_values
    def to_file(self, f):
        f.write(pack(self._fmt,
                             self.encoding.value,
                             self.offset,
                             self.size, self.num_values))

    @classmethod
    def from_file(cls, f):
        enc, off, sz, num_values = unpack(cls._fmt, _read_exact(f, calcsize(cls._fmt)))
        return cls(Encoding(enc), off, sz, num_values)

@dataclass
class ColumnChunk:
    type: Type
    num_values: int
    hybrid_num_values: int
    compression: Compression
    dictionary: Page | None
    data: tuple[Page, ...]


    _fmt = "<BQQB"  # type, num_values, hybrid_num_values, compression
    def to_file(self, f):
        f.write(pack(self._fmt,
                             self.type.value,
                             self.num_values,
                             self.hybrid_num_values,
                             self.compression.value))
        # optional dictionary
        f.write(pack("<B", 1 if self.dictionary else 0))
        if self.dictionary is not None:
            self.dictionary.to_file(f)

        f.write(pack("<I", len(self.data)))
        for data in self.data:
            data.to_file(f)

    @classmethod
    def from_file(cls, f):
        t, nv, hnv, comp = unpack(cls._fmt, _read_exact(f, calcsize(cls._fmt)))

        has_dict, = unpack("<B", _read_exact(f, 1))
        dictionary = Page.from_file(f) if has_dict else None

        (n,) = unpack("<I", _read_exact(f, 4))
        data = tuple(Page.from_file(f) for _ in range(n))

        return cls(Type(t), nv, hnv, Compression(comp), dictionary, data)

@dataclass
class RowGroup:
    chunks: tuple[ColumnChunk, ...]

    def to_file(self, f):
        f.write(pack("<I", len(self.chunks)))
        for c in self.chunks:
            c.to_file(f)

    @classmethod
    def from_file(cls, f):
        (n,) = unpack("<I", _read_exact(f, 4))
        return cls(tuple(ColumnChunk.from_file(f) for _ in range(n)))

@dataclass
class Metadata:
    column_names: tuple[String, ...]
    groups: tuple[RowGroup, ...]

    def to_file(self, f):
        f.write(pack("<I", len(self.column_names)))
        for n in self.column_names:
            n.to_file(f)

        f.write(pack("<I", len(self.groups)))
        for g in self.groups:
            g.to_file(f)

    @classmethod
    def from_file(cls, f):
        (n,) = unpack("<I", _read_exact(f, 4))
        column_names = tuple(String.from_file(f) for _ in range(n))

        (n,) = unpack("<I", _read_exact(f, 4))
        groups = tuple(RowGroup.from_file(f) for _ in range(n))

        return cls(column_names, groups)
