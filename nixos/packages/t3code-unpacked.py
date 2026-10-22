"""Read the unpacked directory glob needed to preserve a release ASAR's layout."""

import json
from pathlib import Path
import struct
import sys


with Path(sys.argv[1]).open("rb") as archive:
  header = struct.unpack("<4I", archive.read(16))
  filesystem = json.loads(archive.read(header[3]))


def unpacked_directories(directory, prefix=""):
  for name, entry in directory["files"].items():
    path = prefix + name
    if "files" in entry:
      if entry.get("unpacked"):
        # ASAR uses minimatch; fail rather than misinterpret a changed layout.
        assert not any(character in path for character in "{}[]*?!,")
        yield path
      else:
        yield from unpacked_directories(entry, path + "/")
    else:
      assert not entry.get("unpacked"), f"Unpacked file outside an unpacked directory: {path}"


paths = list(unpacked_directories(filesystem))
assert paths, "Expected unpacked native module directories"
print("{" + ",".join(paths) + "}")
