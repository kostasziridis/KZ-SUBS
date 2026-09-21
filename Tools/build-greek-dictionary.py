#!/usr/bin/env python3
"""Turn the Greek Hunspell dictionary into something the app can search on a phone.

    python3 Tools/build-greek-dictionary.py [path to el_GR.dic]

The source is the el_GR dictionary from the elspell project, as shipped by
LibreOffice, tri-licensed MPL 1.1 / GPL 2.0 / LGPL 2.1 - we use it under the MPL.
It has no affix rules at all: all 828,806 forms are written out, so no Hunspell
engine is needed, only a way to look a word up.

Words are ordered by their accent-stripped form, because that is the mistake that
actually happens - «καλως» for «καλώς» - so every spelling of the same letters ends
up adjacent and one search finds them all. Only the words are written: the key is
recomputed by stripping accents again at lookup time, which costs nothing and saves
storing every word twice. They are front-coded in blocks of 32, so a block decodes
from its own start, and deflated.
"""
import pathlib, sys, unicodedata, zlib, struct

BLOCK = 32
MAGIC = b"KZGW"
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Sources/Resources/GreekWords.bin"


def fold(word: str) -> str:
    """The word with its accents taken off, which is the form we group by.

    Final sigma becomes an ordinary one as well, so «ΚΑΛΩΣ» and «καλώς» fold alike.
    `GreekSpellChecker.fold` in the app has to do exactly this, or nothing is found.
    """
    stripped = "".join(
        c for c in unicodedata.normalize("NFD", word.lower())
        if unicodedata.category(c) != "Mn"
    )
    return stripped.replace("ς", "σ")


def read_words(path: pathlib.Path) -> set[str]:
    # The file is ISO-8859-7 whatever any mirror claims, and starts with a count.
    text = path.read_bytes().decode("iso-8859-7")
    words = set()
    for line in text.splitlines()[1:]:
        word = line.split("/")[0].strip()
        if word and not word[0].isdigit():
            words.add(word)
    return words


def main() -> int:
    source = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "Tools/el_GR.dic"
    if not source.exists():
        print(f"No dictionary at {source}.\n"
              "Fetch it from https://github.com/LibreOffice/dictionaries/tree/master/el_GR")
        return 1

    words = read_words(source)
    # Sorted by the stripped form first, so all the spellings of one word are together,
    # then by the word itself so the order is stable between builds.
    ordered = sorted(words, key=lambda w: (fold(w), w))

    payload, offsets, previous = bytearray(), [], b""

    for index, word in enumerate(ordered):
        if index % BLOCK == 0:
            offsets.append(len(payload))
            previous = b""  # each block stands alone, so it can be decoded from its start

        # Counted in bytes, not characters, so the app can decode without ever
        # decoding UTF-8 first. A prefix may end mid-character; the bytes still join
        # back into the right word.
        encoded = word.encode("utf-8")
        shared = 0
        limit = min(len(previous), len(encoded), 255)
        while shared < limit and previous[shared] == encoded[shared]:
            shared += 1

        payload.append(shared)
        payload += encoded[shared:]
        payload += b"\n"
        previous = encoded

    # Raw deflate: what Apple's `.zlib` algorithm actually decompresses.
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
    compressed = compressor.compress(bytes(payload)) + compressor.flush()

    header = bytearray(MAGIC)
    header += struct.pack("<BBII", 1, BLOCK, len(ordered), len(offsets))
    header += struct.pack("<I", len(payload))
    header += b"".join(struct.pack("<I", o) for o in offsets)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_bytes(bytes(header) + compressed)

    print(f"{len(ordered):,} words in {len(offsets):,} blocks")
    print(f"payload {len(payload)/1e6:.1f} MB -> {OUT.name} {OUT.stat().st_size/1e6:.2f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
