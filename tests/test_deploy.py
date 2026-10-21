"""Exercise download/integrity/preflight behavior without any real SSH calls."""
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLKIT_REV = "3555e95650233474862fc1e3a0a4ce92709a9bd2"
INJECTOR_REV = "d9338952cd01597c5fdd7d6e98991474df5dc89c"


def elf(machine=40, hard_float=False):
    header = bytearray(40)
    header[:7] = b"\x7fELF\x01\x01\x01"
    header[18:20] = machine.to_bytes(2, "little")
    header[37] = 4 if hard_float else 2
    header[39] = 5
    return bytes(header) + b"test fixture\n"


class DeployTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="magic-pointer-tests-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.project = self.base / "project with spaces"
        self.project.mkdir()
        shutil.copy2(ROOT / "deploy.sh", self.project)
        for folder in ("scripts", "releases", "tv"):
            shutil.copytree(ROOT / folder, self.project / folder)
        self.payloads = {
            "ezinject": elf(),
            "libphpbridge.so": elf() + b"bridge",
            "ezinject-revision": (INJECTOR_REV + "\n").encode(),
        }
        manifest = "".join(
            f"{hashlib.sha256(data).hexdigest()}  {name}\n"
            for name, data in self.payloads.items()
        )
        (self.project / "releases/v1.0.0.sha256").write_text(manifest)
        self.archive = self.base / "toolkit.tar.gz"
        self.write_archive()
        self.ref = self.project / "lginputhook-ref"
        (self.ref / ".git").mkdir(parents=True)
        ih = self.ref / "service/inputhook"
        for name in ("ezinject", "hookfactory.php", "libcrypt1/libphp.so", "libcrypt2/libphp.so"):
            target = ih / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"<?php fixture" if name.endswith(".php") else elf())
        self.clone_payload = self.base / "clone-payload"
        shutil.copytree(self.ref, self.clone_payload)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        CASE=str(self.base), ARCHIVE=str(self.archive),
                        CLONE_PAYLOAD=str(self.clone_payload), HEAD=TOOLKIT_REV,
                        LIBC="glibc 2.39", UID_RESULT="0", HEADER=" ".join(map(str, elf()[:40])))
        self.mock("ssh", '''
command = sys.argv[-1]
if command == "true": pass
elif command == "id -u": print(os.environ["UID_RESULT"])
elif command.startswith("set -- $(pidof lginput2)"): print(os.environ["HEADER"])
elif "getconf GNU_LIBC_VERSION" in command: print(os.environ["LIBC"])
elif "echo libcrypt2" in command: print("libcrypt2")
else:
    with open(os.environ["CASE"] + "/writes", "a") as f: f.write(command + "\\n")
    if "cat >" in command: sys.stdin.buffer.read()
    if "--once" in command and os.environ.get("INJECT_FAIL"): sys.exit(1)
''')
        self.mock("git", '''
args = sys.argv[1:]
if "clone" in args: shutil.copytree(os.environ["CLONE_PAYLOAD"], args[-1])
elif "rev-parse" in args: print(os.environ["HEAD"])
elif "status" in args and os.environ.get("DIRTY"): print(" M user-change")
else:
    with open(os.environ["CASE"] + "/git-operations", "a") as f: f.write(" ".join(args) + "\\n")
''')
        self.mock("curl", '''
args = sys.argv[1:]
shutil.copyfile(os.environ["ARCHIVE"], args[args.index("--output") + 1])
with open(os.environ["CASE"] + "/downloads", "a") as f: f.write(args[-1] + "\\n")
''')

    def mock(self, name, body):
        path = self.bin / name
        path.write_text(f"#!{sys.executable}\nimport os, shutil, sys\n" + body)
        path.chmod(0o755)

    def write_archive(self, extra=None):
        with tarfile.open(self.archive, "w:gz") as archive:
            for name, data in self.payloads.items():
                member = tarfile.TarInfo(name)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
            if extra:
                member = tarfile.TarInfo(extra)
                member.size = 7
                archive.addfile(member, io.BytesIO(b"outside"))

    def run_deploy(self, *options, success=True):
        result = subprocess.run(["sh", str(self.project / "deploy.sh"), *options, "test-tv"],
                                env=self.env, capture_output=True, text=True, input="")
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def writes(self):
        path = self.base / "writes"
        return path.read_text() if path.exists() else ""

    def test_fresh_modern_check_downloads_and_never_writes_tv(self):
        shutil.rmtree(self.ref)
        self.run_deploy("--check")
        self.assertEqual(self.writes(), "")
        self.assertTrue((self.base / "downloads").exists())
        self.assertTrue((self.ref / "service/inputhook/hookfactory.php").exists())

    def test_valid_cache_does_not_download_again(self):
        self.run_deploy("--check")
        self.run_deploy("--check")
        self.assertEqual(len((self.base / "downloads").read_text().splitlines()), 1)

    def test_changed_cache_is_replaced_by_verified_release(self):
        self.run_deploy("--check")
        cache = self.project / ".build/modern/ezinject"
        cache.write_bytes(b"changed")
        self.run_deploy("--check")
        self.assertEqual(cache.read_bytes(), self.payloads["ezinject"])

    def test_corrupt_release_never_reaches_tv(self):
        self.payloads["libphpbridge.so"] += b"changed"
        self.write_archive()
        result = self.run_deploy("--check", success=False)
        self.assertIn("checksum", result.stderr)
        self.assertEqual(self.writes(), "")

    def test_archive_extra_paths_are_not_extracted(self):
        self.write_archive(extra="../../escaped")
        self.run_deploy("--check")
        self.assertFalse((self.project / "escaped").exists())
        self.assertFalse((self.base / "escaped").exists())

    def test_unprivileged_ssh_is_rejected_before_download(self):
        self.env["UID_RESULT"] = "1000"
        self.run_deploy("--check", success=False)
        self.assertEqual(self.writes(), "")
        self.assertFalse((self.base / "downloads").exists())

    def test_unsupported_architectures_are_rejected(self):
        for header in (elf(machine=183), elf(hard_float=True)):
            self.env["HEADER"] = " ".join(map(str, header[:40]))
            self.run_deploy("--check", success=False)
            self.assertEqual(self.writes(), "")

    def test_unknown_libc_is_rejected(self):
        self.env["LIBC"] = "unknown"
        self.run_deploy("--check", success=False)
        self.assertEqual(self.writes(), "")

    def test_legacy_does_not_download_modern_release(self):
        self.env["LIBC"] = "glibc 2.31"
        self.run_deploy("--check")
        self.assertFalse((self.base / "downloads").exists())
        self.assertEqual(self.writes(), "")

    def test_missing_php_payload_stops_before_writes(self):
        (self.ref / "service/inputhook/hookfactory.php").unlink()
        self.run_deploy(success=False)
        self.assertEqual(self.writes(), "")

    def test_dirty_old_clone_is_preserved(self):
        self.env.update(HEAD="old", DIRTY="yes")
        self.run_deploy(success=False)
        self.assertEqual(self.writes(), "")
        self.assertFalse((self.base / "git-operations").exists())

    def test_failed_injection_does_not_install_autostart(self):
        self.env["INJECT_FAIL"] = "yes"
        self.run_deploy(success=False)
        self.assertNotIn("cat > '/var/lib/webosbrew/init.d/disable-magic-pointer", self.writes())

    def test_success_installs_autostart_after_once_injection(self):
        self.run_deploy()
        writes = self.writes()
        self.assertLess(writes.index("--once"), writes.index("cat > '/var/lib/webosbrew/init.d/disable-magic-pointer"))
        self.assertIn(".upload-", writes)
        self.assertIn("mv -f", writes)

    def test_local_build_requires_its_manifest_and_never_downloads(self):
        self.run_deploy("--local-build", "--check", success=False)
        cache = self.project / ".build/modern"
        cache.mkdir(parents=True)
        for name, data in self.payloads.items():
            (cache / name).write_bytes(data)
        shutil.copyfile(self.project / "releases/v1.0.0.sha256", cache / "build-manifest.sha256")
        self.run_deploy("--local-build", "--check")
        self.assertFalse((self.base / "downloads").exists())
        self.assertEqual(self.writes(), "")


if __name__ == "__main__":
    unittest.main()
