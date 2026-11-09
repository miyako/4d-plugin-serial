"""Selective cleanup and final-only generation allowances for actual macOS outputs."""

import shutil
from unittest import mock

from helper_support import Fixture, GitFixture, cwd
import native
import repository


class NativePreparationTests(Fixture):
    def test_selective_cleanup_preserves_prebuilt_resources_dependencies_and_siblings(self):
        protected = (
            native.BUNDLE / "Contents/QuickLook/Thumbnail.png",
            native.BUNDLE / "Contents/MacOS/runtime.dylib",
            native.BUNDLE / "Contents/Resources/custom.txt",
            native.BUNDLE / "Contents/Windows/Serial.4DX",
            native.BUNDLE / "Contents/Windows64/Serial.4DX",
            native.BASE / "Default/Serial.bundle/Contents/Info.plist",
            native.BASE / "Default/keep", native.BASE / "Other.bundle/keep",
            "build/unrelated/keep", "a/liborsserialport.a", "lib/windows64/jsoncpp.lib",
        )
        for path in protected:
            self.write(path, b"preserved")
        for path in native.FILES:
            self.write(path, b"stale")
        for path in native.DIRECTORIES:
            self.write(path / "intermediate", b"stale")
        with cwd(self.root):
            native.prepare()
            native.prepare()
        for path in protected:
            self.assertEqual((self.root / path).read_bytes(), b"preserved")
        for path in (*native.FILES, *native.DIRECTORIES):
            self.assertFalse((self.root / path).exists(), path)

    def test_symlink_anywhere_prevalidated_before_first_deletion(self):
        for where in (native.FILES[-1], native.DIRECTORIES[-1], native.BUNDLE,
                      native.DIRECTORIES[0] / "nested/link"):
            with self.subTest(where=where):
                first = self.write(native.FILES[0], b"must remain")
                destination = self.write("outside/keep", b"untouched")
                link = self.root / where
                if link.is_dir():
                    shutil.rmtree(link)
                link.parent.mkdir(parents=True, exist_ok=True)
                link.symlink_to(destination)
                with cwd(self.root), self.assertRaisesRegex(ValueError, "symlink"):
                    native.prepare()
                if where != native.BUNDLE:
                    self.assertEqual(first.read_bytes(), b"must remain")
                self.assertEqual(destination.read_bytes(), b"untouched")
                link.unlink()

    def test_cleanup_io_error_is_fatal(self):
        self.write(native.FILES[0], b"stale")
        with cwd(self.root), mock.patch("pathlib.Path.unlink", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                native.prepare()
        self.write(native.DIRECTORIES[0] / "stale", b"stale")
        with cwd(self.root), mock.patch("shutil.rmtree", side_effect=PermissionError("denied")):
            with self.assertRaises(PermissionError):
                native.prepare()

    def test_resources_are_exact_source_copies_and_both_windows_binaries_required(self):
        for name in ("constants.xlf", "manifest.json"):
            self.write(name, b"source")
            self.write(native.BUNDLE / "Contents/Resources" / name, b"source")
        for platform in ("Windows", "Windows64"):
            self.write(native.BUNDLE / f"Contents/{platform}/Serial.4DX", b"prebuilt")
        with cwd(self.root):
            native.verify_resources()
            copied = native.BUNDLE / "Contents/Resources/constants.xlf"
            copied.write_bytes(b"stale")
            with self.assertRaisesRegex(ValueError, "differs"):
                native.verify_resources()
            copied.write_bytes(b"source")
            for platform in ("Windows", "Windows64"):
                path = native.BUNDLE / f"Contents/{platform}/Serial.4DX"
                path.write_bytes(b"")
                with self.assertRaisesRegex(ValueError, "Missing or empty"):
                    native.verify_resources()
                path.write_bytes(b"prebuilt")


class GeneratedRetentionTests(GitFixture):
    def test_actual_database_wal_and_outputs_are_final_only(self):
        for relative in (
            *native.FILES, "build/XCBuildData/build.db",
            "build/XCBuildData/build.db-wal", "build/XCBuildData/build.db-shm",
            "build/XCBuildData/43cb86982ef48addb679abbcf73e7bf0.xcbuilddata/build-request.json",
            "build/Serial.build/Default/Serial.build/Objects-normal/arm64/main.o",
            "build/Default/Serial.build/main.o",
        ):
            target = self.local / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"fresh native output")
        with cwd(self.local):
            with self.assertRaises(ValueError):
                repository.verify_checkout(self.sha, generated=native.generated)
            repository.verify_checkout(self.sha, generated=native.generated, final=True)

    def test_evil_siblings_and_protected_resources_never_gain_exemption(self):
        for relative in (
            "build/XCBuildData-evil/build.db",
            "build/XCBuildData/unexpected-source.cpp",
            "build/XCBuildData/build.db-evil",
            "build/XCBuildData/evil.xcbuilddata/source.cpp",
            "build/Serial.build-evil/main.o", "build/unexpected-source.cpp",
            "Objs/Release/main.obj", "winbuild/Serial.4DX",
            "test/Plugins/Default/Serial.bundle/Contents/Info.plist",
            str(native.BUNDLE / "Contents/QuickLook/Thumbnail.png"),
            str(native.BUNDLE / "Contents/MacOS/runtime.dylib"),
            str(native.BUNDLE / "Contents/Windows64/Serial.4DX"),
            str(native.BUNDLE / "Contents/Resources/custom.txt"),
            str(native.BUNDLE / "Contents/_CodeSignature/evil"),
        ):
            with self.subTest(relative=relative):
                target = self.local / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b"unexpected")
                with cwd(self.local), self.assertRaises(ValueError):
                    repository.verify_checkout(self.sha, generated=native.generated, final=True)
                target.unlink()

    def test_generated_tracked_index_changes_are_not_allowed(self):
        path = self.local / native.FILES[0]
        path.parent.mkdir(parents=True)
        path.write_bytes(b"original generated output")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "tracked generated fixture")
        sha = self.git("rev-parse", "HEAD")
        path.write_bytes(b"new output")
        with cwd(self.local):
            repository.verify_checkout(sha, generated=native.generated, final=True)
        self.git("add", ".")
        with cwd(self.local), self.assertRaisesRegex(ValueError, "Index"):
            repository.verify_checkout(sha, generated=native.generated, final=True)
