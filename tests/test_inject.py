"""Behavioral tests for the boot injector using a disposable process fixture."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class InjectorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="magic-pointer-inject-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.proc = self.base / "proc"
        self.proc.mkdir()
        self.tmp = self.base / "tmp"
        self.tmp.mkdir()
        (self.proc / "uptime").write_text("123.45 67.89\n")
        self.dir = self.base / "inputhook"
        for variant in ("libcrypt1", "libcrypt2"):
            (self.dir / variant).mkdir(parents=True)
        for file in ("ezinject", "hookfactory.php", "pointer-hook.php",
                     "libcrypt1/libphp.so", "libcrypt2/libphp.so"):
            (self.dir / file).write_text("fixture\n")
        (self.dir / "toolkit-mode").write_text("legacy\n")
        self.pid = "4289"
        self.status(self.pid, "S", 0)
        self.maps(self.pid, "")
        self.pidof_log = self.base / "pidof.log"
        self.ezinject_log = self.base / "ezinject.log"
        self.kill_log = self.base / "kill.log"
        self.sleep_log = self.base / "sleep.log"
        self.script = self.base / "inject-pointer-hook.sh"
        source = (ROOT / "tv/inject-pointer-hook.sh").read_text()
        replacements = {
            "/proc/": f"{self.proc}/",
            "/tmp/": f"{self.tmp}/",
            "/home/root/magic-pointer/inputhook": str(self.dir),
            "/home/root/magic-pointer/inject.log": str(self.base / "inject.log"),
            "/home/root/magic-pointer/module.log": str(self.base / "module.log"),
        }
        # Substitute in one pass so inserted /tmp paths are never rewritten.
        source = re.sub("|".join(map(re.escape, replacements)),
                        lambda match: replacements[match.group()], source)
        self.script.write_text(source)
        self.script.chmod(0o755)
        self.command("pidof", '''
import os, pathlib, sys
log = pathlib.Path(os.environ["PIDOF_LOG"])
with log.open("a") as f: f.write(" ".join(sys.argv[1:]) + "\\n")
mode = os.environ.get("PID_MODE", "single")
if mode == "multi": print("4289 4290")
elif mode == "nonnumeric": print("not-a-pid")
elif mode == "changed" and pathlib.Path(os.environ["EZINJECT_LOG"]).exists(): print("4290")
else: print(os.environ.get("PID", "4289"))
''')
        self.command("ezinject", '''
import os, pathlib, sys
with pathlib.Path(os.environ["EZINJECT_LOG"]).open("a") as f: f.write("called\\n")
if os.environ.get("EZ_MODE") == "ready":
    pid = os.environ["PID"]
    pathlib.Path(os.environ["PROC"] + "/" + pid + "/maps").write_text("libphp.so\\n")
    pathlib.Path(os.environ["TMPDIR"] + "/magic-pointer-ready-" + pid).write_text("installed settings-dpad-v1\\n")
if os.environ.get("EZ_MODE") in ("stop-ready", "stop-fail", "stop-traced", "stop-lowercase"):
    status = pathlib.Path(os.environ["PROC"] + "/" + os.environ["PID"] + "/status")
    contents = status.read_text().replace("State:\\tS ", "State:\\tT ")
    if os.environ["EZ_MODE"] == "stop-traced": contents = contents.replace("TracerPid:\\t0", "TracerPid:\\t77")
    if os.environ["EZ_MODE"] == "stop-lowercase": contents = contents.replace("State:\\tT ", "State:\\tt ")
    status.write_text(contents)
if os.environ.get("EZ_MODE") in ("fail", "stop-fail"): sys.exit(1)
''')
        (self.dir / "ezinject").unlink()
        (self.dir / "ezinject").symlink_to(self.bin / "ezinject")
        self.command("sleep", '''
import os, pathlib, sys
with pathlib.Path(os.environ["SLEEP_LOG"]).open("a") as f: f.write(" ".join(sys.argv[1:]) + "\\n")
''')

    def command(self, name, body):
        path = self.bin / name
        path.write_text(f"#!{os.sys.executable}\n" + body)
        path.chmod(0o755)

    def status(self, pid, state, tracer):
        folder = self.proc / pid
        folder.mkdir(exist_ok=True)
        (folder / "status").write_text(f"Name:\tlginput2\nState:\t{state} (fixture)\nTracerPid:\t{tracer}\n")

    def maps(self, pid, content):
        folder = self.proc / pid
        folder.mkdir(exist_ok=True)
        (folder / "maps").write_text(content)

    def run_script(self, **extra):
        # A shell function intercepts only the production script's CONT action.
        # It simulates the kernel resuming this fixture and PHP publishing ready.
        wrapper = self.base / "run.sh"
        wrapper.write_text(f'''#!/bin/sh
kill() {{
    printf '%s\\n' "$*" >> "{self.kill_log}"
    if [ "$1" = -CONT ] && [ "$2" = "{self.pid}" ]; then
        sed 's/State:\\tT /State:\\tS /' "{self.proc}/{self.pid}/status" > "{self.proc}/{self.pid}/status.new"
        mv "{self.proc}/{self.pid}/status.new" "{self.proc}/{self.pid}/status"
        echo libphp.so >> "{self.proc}/{self.pid}/maps"
        printf 'installed settings-dpad-v1\\n' > "{self.tmp}/magic-pointer-ready-{self.pid}"
    fi
}}
set -- --once
. "{self.script}"
''')
        wrapper.chmod(0o755)
        env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                   PID=self.pid, PROC=str(self.proc), TMPDIR=str(self.tmp),
                   PIDOF_LOG=str(self.pidof_log), EZINJECT_LOG=str(self.ezinject_log),
                   SLEEP_LOG=str(self.sleep_log), PID_MODE="single", EZ_MODE="ready")
        env.update(extra)
        return subprocess.run([env.get("TEST_SHELL", "/bin/sh"), str(wrapper)],
                              env=env, capture_output=True, text=True, timeout=15)

    def calls(self):
        return self.ezinject_log.read_text().splitlines() if self.ezinject_log.exists() else []

    def resumes(self):
        return self.kill_log.read_text().splitlines() if self.kill_log.exists() else []

    def test_requires_one_numeric_pid_before_injection(self):
        for mode in ("multi", "nonnumeric"):
            with self.subTest(mode=mode):
                result = self.run_script(PID_MODE=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.calls(), [])

    def test_refuses_stopped_process_before_injection(self):
        self.status(self.pid, "T", 0)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.resumes(), [])

    def test_refuses_traced_process_before_injection(self):
        self.status(self.pid, "S", 321)
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.resumes(), [])

    def test_resumes_own_untraced_stopped_process_after_successful_ezinject(self):
        result = self.run_script(EZ_MODE="stop-ready")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr + (self.base / "inject.log").read_text())
        self.assertEqual(self.calls(), ["called"], (self.base / "inject.log").read_text())
        self.assertEqual(self.resumes(), [f"-CONT {self.pid}"])

    def test_resumes_after_failed_ezinject_but_still_returns_failure_without_retry(self):
        result = self.run_script(EZ_MODE="stop-fail")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), ["called"], (self.base / "inject.log").read_text())
        self.assertEqual(self.resumes(), [f"-CONT {self.pid}"])
        self.assertEqual(len(self.sleep_log.read_text().splitlines()) if self.sleep_log.exists() else 0, 0)

    def test_never_resumes_tracing_stop(self):
        result = self.run_script(EZ_MODE="stop-lowercase")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.resumes(), [])

    def test_never_resumes_process_that_changed_during_injection(self):
        # Change pidof's answer as soon as ezinject returns.
        result = self.run_script(PID_MODE="changed", EZ_MODE="none")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), ["called"])
        self.assertEqual(self.resumes(), [])

    def test_never_resumes_a_traced_stopped_process_after_ezinject(self):
        result = self.run_script(EZ_MODE="stop-traced")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.resumes(), [])

    def test_normal_running_process_needs_no_resume(self):
        result = self.run_script(EZ_MODE="ready")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.resumes(), [])

    def test_already_ready_process_skips_injection_and_resume(self):
        self.maps(self.pid, "libphp.so\n")
        (self.tmp / f"magic-pointer-ready-{self.pid}").write_text("installed settings-dpad-v1\n")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.resumes(), [])


if __name__ == "__main__":
    unittest.main()
