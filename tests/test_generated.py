"""The final publication exemption is smaller than the bundle or build roots."""

import unittest

from helper_support import source
import native


class GeneratedOutputTests(unittest.TestCase):
    def test_exact_native_files_and_controlled_directory_descendants(self):
        expected = (
            "test/Plugins/Serial.bundle/Contents/MacOS/Serial",
            "test/Plugins/Serial.bundle/Contents/Info.plist",
            "test/Plugins/Serial.bundle/Contents/Resources/English.lproj/InfoPlist.strings",
            "test/Plugins/Serial.bundle/Contents/_CodeSignature/CodeResources",
            "test/Plugins/Serial.bundle/Contents/Resources/constants.xlf",
            "test/Plugins/Serial.bundle/Contents/Resources/manifest.json",
            "build/XCBuildData/build.db",
            "build/XCBuildData/build.db-wal",
            "build/Serial.build/Objects-normal/arm64/main.o",
            "build/Default/Serial.build/build.db",
            "test/Plugins/Serial.build/Objects/file.o",
            "test/Plugins/Default/Serial.build/Objects/file.o",
        )
        for path in expected:
            with self.subTest(path=path):
                self.assertTrue(native.generated(path))

    def test_every_resource_source_or_unproven_output_stays_protected(self):
        excluded = (
            "test/Plugins/Serial.bundle/Contents/Windows/Serial.4DX",
            "test/Plugins/Serial.bundle/Contents/Windows64/Serial.4DX",
            "test/Plugins/Serial.bundle/Contents/MacOS/runtime.dylib",
            "test/Plugins/Serial.bundle/Contents/QuickLook/Thumbnail.png",
            "test/Plugins/Default/Serial.bundle/Contents/Info.plist",
            "test/Plugins/Default/keep", "build/XCBuildData-evil/build.db",
            "build/unexpected-source.cpp",
            "build/Serial.build-evil/injected.cpp",
            "test/Plugins/Serial.bundle/Contents/_CodeSignature-evil/file",
            "test/Plugins/Serial.bundle/Contents/Info.plist.backup",
            *map(str, source.SOURCE_PATHS),
        )
        for path in excluded:
            with self.subTest(path=path):
                self.assertFalse(native.generated(path))
