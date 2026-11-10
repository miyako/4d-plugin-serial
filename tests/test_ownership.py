"""Compile real plugin sources and unchanged SDK against a device-free engine."""

import os
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(platform.system() == "Darwin", "Objective-C++ macOS boundary")
class Ownership(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="serial-ownership-")
        cls.addClassCleanup(cls.temp.cleanup)
        build = Path(cls.temp.name)
        source = ROOT
        ref = os.environ.get("SERIAL_OWNERSHIP_REF")
        if ref:
            source = build / "baseline"
            files = subprocess.check_output(
                ["git", "ls-tree", "-r", "--name-only", ref], cwd=ROOT,
                text=True).splitlines()
            for name in files:
                if (name.startswith(("4D Plugin API/", "support/", "include/"))
                        or name in ("4DPlugin-Serial.cpp", "4DPlugin-Serial.h")):
                    target = source / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(subprocess.check_output(
                        ["git", "show", f"{ref}:{name}"], cwd=ROOT))
        flags = ["-g", "-O1", "-fsanitize=address,undefined",
                 "-fno-omit-frame-pointer", "-Wno-deprecated-declarations",
                 "-Wno-incompatible-pointer-types", "-Wno-incomplete-implementation"]
        includes = [f"-I{source}", f"-I{source / '4D Plugin API'}",
                    f"-I{source / '4D Plugin API/Classes'}",
                    f"-I{source / 'support'}", f"-I{source / 'include'}"]
        sdk = build / "sdk.o"
        subprocess.run(["xcrun", "clang", *flags, "-Wno-int-conversion",
                        "-Wno-multichar", *includes, "-c",
                        str(source / "4D Plugin API/4DPluginAPI.c"),
                        "-o", str(sdk)], check=True)
        cls.binary = build / "ownership"
        subprocess.run([
            "xcrun", "clang++", "-std=c++11", *flags, *includes, "-x", "objective-c++",
            str(ROOT / "tests/ownership.mm"),
            str(source / "4DPlugin-Serial.cpp"),
            str(source / "support/4DPlugin-JSON.cpp"),
            str(source / "4D Plugin API/Classes/C_TEXT.cpp"),
            str(source / "4D Plugin API/Classes/ARRAY_TEXT.cpp"),
            "-x", "none", str(sdk), "-framework", "Cocoa",
            "-framework", "CoreFoundation", "-framework", "CoreGraphics",
            "-o", str(cls.binary)], check=True)

    def run_case(self, case):
        subprocess.run([str(self.binary), case], check=True,
                       env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0",
                            "UBSAN_OPTIONS": "halt_on_error=1"})

    def test_setters(self):
        self.run_case("setters")

    def test_properties(self):
        self.run_case("properties")

    def test_collection_handoff(self):
        self.run_case("collection")

    def test_method_callback(self):
        self.run_case("method")

    def test_command_callback(self):
        self.run_case("command")

    def test_arrays(self):
        self.run_case("arrays")


if __name__ == "__main__":
    unittest.main()
