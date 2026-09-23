# Copyright (C) 2026 Shitty team
# MIT licensed
# See the file LICENSE.MIT for the full license.

import importlib.util
import tarfile
import tempfile
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "release",
    ROOT / "dev" / "release.py",
)
RELEASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RELEASE)

TIMESTAMP = 1_700_000_000


def build_bundle(root, executable_mode, plist_mode):
    bundle = root / "Shitty.app"
    (bundle / "Contents" / "MacOS").mkdir(parents=True)
    (bundle / "Contents" / "Resources").mkdir()
    executable = bundle / "Contents" / "MacOS" / "st"
    executable.write_bytes(b"\xcf\xfa\xed\xfe fake mach-o")
    executable.chmod(executable_mode)
    plist = bundle / "Contents" / "Info.plist"
    plist.write_text("<plist/>")
    plist.chmod(plist_mode)
    (bundle / "Contents" / "Resources" / "shitty.icns").write_bytes(b"icns")
    return bundle


class BundleArchiveTest(unittest.TestCase):
    def test_modes_come_from_structure_not_from_the_source_tree(self):
        # actions/download-artifact hands the release script a bundle with
        # its modes stripped; the archive must ship a 755 executable and
        # 644 data files regardless of what the filesystem says.
        with tempfile.TemporaryDirectory() as directory:
            bundle = build_bundle(Path(directory), 0o644, 0o755)
            output = Path(directory) / "bundle.tar.gz"
            RELEASE.create_directory_archive(bundle, output, TIMESTAMP)

            with tarfile.open(output) as archive:
                modes = {
                    member.name: member.mode for member in archive.getmembers()
                }
                owners = {
                    (member.uid, member.gid, member.uname, member.gname)
                    for member in archive.getmembers()
                }
                times = {member.mtime for member in archive.getmembers()}

        self.assertEqual(modes["Shitty.app/Contents/MacOS/st"], 0o755)
        self.assertEqual(modes["Shitty.app/Contents/Info.plist"], 0o644)
        self.assertEqual(modes["Shitty.app/Contents/Resources/shitty.icns"], 0o644)
        self.assertEqual(modes["Shitty.app"], 0o755)
        self.assertEqual(modes["Shitty.app/Contents"], 0o755)
        self.assertEqual(modes["Shitty.app/Contents/MacOS"], 0o755)
        self.assertEqual(owners, {(0, 0, "", "")})
        self.assertEqual(times, {TIMESTAMP})

    def test_archive_bytes_do_not_depend_on_source_modes(self):
        archives = []
        for executable_mode, plist_mode in ((0o644, 0o644), (0o755, 0o600)):
            with tempfile.TemporaryDirectory() as directory:
                bundle = build_bundle(Path(directory), executable_mode, plist_mode)
                output = Path(directory) / "bundle.tar.gz"
                RELEASE.create_directory_archive(bundle, output, TIMESTAMP)
                archives.append(output.read_bytes())
        self.assertEqual(archives[0], archives[1])

    def test_symlink_in_a_bundle_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = build_bundle(Path(directory), 0o755, 0o644)
            (bundle / "Contents" / "MacOS" / "st2").symlink_to("st")
            output = Path(directory) / "bundle.tar.gz"
            with self.assertRaisesRegex(RuntimeError, "unsupported symlink"):
                RELEASE.create_directory_archive(bundle, output, TIMESTAMP)


if __name__ == "__main__":
    unittest.main()
