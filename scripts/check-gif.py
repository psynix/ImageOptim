#!/usr/bin/env python3
"""Check the bundled GIF optimiser against upstream animation regressions."""

import base64
import pathlib
import re
import subprocess
import sys
import tempfile


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    source = root / "gifsicle/orig"
    engine = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root / "imageoptim/build/Build/Products/Release/gifsicle"
    baseline = pathlib.Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None
    flags = ["-O3", "--careful", "--no-comments", "--no-names", "--same-delay", "--same-loopcount", "--no-warnings", "--no-ignore-errors"]
    assert engine.is_file(), "Build ImageOptim first, or pass the Gifsicle executable path"

    with tempfile.TemporaryDirectory(prefix="imageoptim-gif-check-") as directory:
        work = pathlib.Path(directory)
        gifdiff = work / "gifdiff"
        files = [source / "src" / (name + ".c") for name in ["clp", "fmalloc", "giffunc", "gifread", "gifdiff"]]
        subprocess.run(["xcrun", "clang", "-std=gnu11", "-O2", "-DHAVE_CONFIG_H", "-I", str(root / "gifsicle"), "-I", str(source / "include"), *map(str, files), "-o", str(gifdiff)], check=True)
        tested = rejected = compared = new_bytes = old_bytes = kept_new_bytes = kept_old_bytes = 0
        for spec in sorted((source / "test").glob("*.testie")):
            blocks = re.finditer(r"^%file -e ([^\n]*\.gif)\n(.*?)(?=^%|\Z)", spec.read_text(), re.M | re.S)
            for index, block in enumerate(blocks):
                data = base64.b64decode(block[2])
                if not data.startswith((b"GIF87a", b"GIF89a")):
                    continue
                original = work / f"{spec.stem}-{index}.gif"
                original.write_bytes(data)
                valid = subprocess.run([str(engine), "--info", "--no-ignore-errors", str(original)], capture_output=True).returncode == 0
                if not valid:
                    rejected += 1
                    continue
                for interlace in ["--no-interlace", "--interlace"]:
                    output = work / "output.gif"
                    result = subprocess.run([str(engine), *flags, interlace, "-o", str(output), "--", str(original)], capture_output=True)
                    if spec.stem == "017-maxscreen" and result.returncode != 0:
                        assert b"output screen size" in result.stderr
                        rejected += 1
                        break
                    assert result.returncode == 0, f"Optimisation failed for {original.name}: {result.stderr.decode()}"
                    equal = subprocess.run([str(gifdiff), str(original), str(output)], capture_output=True)
                    assert equal.returncode == 0, f"Appearance or timing changed in {original.name}: {equal.stdout.decode()}"
                    tested += 1
                    if baseline:
                        old_output = work / "baseline.gif"
                        old = subprocess.run([str(baseline), *flags, interlace, "-o", str(old_output), "--", str(original)], capture_output=True)
                        if old.returncode == 0 and subprocess.run([str(gifdiff), str(original), str(old_output)], capture_output=True).returncode == 0:
                            compared += 1
                            new_bytes += output.stat().st_size
                            old_bytes += old_output.stat().st_size
                            kept_new_bytes += min(len(data), output.stat().st_size)
                            kept_old_bytes += min(len(data), old_output.stat().st_size)
        assert tested >= 60, f"Expected the upstream animation corpus, checked only {tested} cases"
        print(f"GIF appearance, delays and loops: {tested} cases passed; {rejected} malformed/unsupported inputs rejected")
        if baseline:
            print(f"Matched baseline: {compared} cases, old {old_bytes} bytes, new {new_bytes} bytes")
            print(f"With the app's smaller-output rule: old {kept_old_bytes} bytes, new {kept_new_bytes} bytes")


if __name__ == "__main__":
    main()
