#!/usr/bin/env python3
"""Run moondbg REPL flows against real and deterministic fake adapters."""

from __future__ import annotations

import argparse
import errno
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
DWARF_PROBE = ROOT / "testdata" / "dwarf_probe"
EXIT_PROBE = ROOT / "testdata" / "exit_probe" / "main.c"
FAKE_DAP = ROOT / "tools" / "fake_dap.py"


class ReplError(RuntimeError):
    pass


class PtyProcess:
    def __init__(
        self,
        argv: list[str],
        *,
        cwd: Path,
        env: dict[str, str],
        timeout: float,
    ) -> None:
        self.started_at = time.monotonic()
        self.initial_prompt_elapsed = 0.0
        master, slave = pty.openpty()
        self.master = master
        self.timeout = timeout
        self.buffer = bytearray()
        self.cursor = 0
        try:
            self.process = subprocess.Popen(
                argv,
                cwd=cwd,
                env=env,
                stdin=slave,
                stdout=slave,
                stderr=slave,
                start_new_session=True,
            )
        finally:
            os.close(slave)
        self.process_group = self.process.pid

    def _read_once(self, deadline: float) -> bool:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        ready, _, _ = select.select([self.master], [], [], remaining)
        if not ready:
            return False
        try:
            chunk = os.read(self.master, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                return False
            raise
        if not chunk:
            return False
        self.buffer.extend(chunk)
        return True

    def expect(self, text: str) -> None:
        needle = text.encode()
        deadline = time.monotonic() + self.timeout
        while True:
            found = self.buffer.find(needle, self.cursor)
            if found >= 0:
                self.cursor = found + len(needle)
                return
            if not self._read_once(deadline):
                raise ReplError(
                    f"timed out waiting for {text!r}\n\n{self.transcript()}"
                )

    def send(self, command: str) -> None:
        os.write(self.master, (command + "\n").encode())

    def send_bytes(self, data: bytes) -> None:
        os.write(self.master, data)

    def wait(self) -> int:
        deadline = time.monotonic() + self.timeout
        while self.process.poll() is None:
            self._read_once(deadline)
            if time.monotonic() >= deadline:
                raise ReplError(
                    f"process did not exit: {self.process.args!r}\n\n"
                    + self.transcript()
                )
        while self._read_once(time.monotonic() + 0.05):
            pass
        return self.process.returncode

    def transcript(self) -> str:
        return self.buffer.decode(errors="replace").replace("\r", "")

    def close(self) -> None:
        os.close(self.master)
        if self.process.poll() is None:
            os.killpg(self.process_group, signal.SIGTERM)
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                os.killpg(self.process_group, signal.SIGKILL)
                self.process.wait(timeout=2)


def require_development_environment() -> tuple[Path, Path]:
    moon_home_value = os.environ.get("MOON_HOME")
    expected = Path.home() / ".moon_dev"
    if not moon_home_value or Path(moon_home_value).resolve() != expected.resolve():
        raise ReplError("MOON_HOME must be ~/.moon_dev; run set_moon_dev first")
    moon = expected / "bin" / "moon"
    moondbg = expected / "bin" / "moondbg"
    for executable in (moon, expected / "bin" / "moonc", moondbg):
        if not executable.is_symlink() or not executable.exists():
            raise ReplError(f"development tool link is invalid: {executable}")
    return moon, moondbg


def assert_no_process_group(process_group: int) -> None:
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        listing = subprocess.run(
            ["ps", "-axo", "pgid=,command="],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout
        members = [
            line
            for line in listing.splitlines()
            if line.strip().split(maxsplit=1)
            and line.strip().split(maxsplit=1)[0] == str(process_group)
        ]
        if not members:
            return
        time.sleep(0.05)
    raise ReplError(
        f"process group {process_group} still has members:\n" + "\n".join(members)
    )


def run_session(
    argv: list[str],
    *,
    cwd: Path,
    env: dict[str, str],
    timeout: float,
    drive,
) -> str:
    session = PtyProcess(argv, cwd=cwd, env=env, timeout=timeout)
    process_group = session.process_group
    try:
        session.expect("(moondbg) ")
        session.initial_prompt_elapsed = time.monotonic() - session.started_at
        drive(session)
        return_code = session.wait()
        if return_code != 0:
            raise ReplError(
                f"{argv!r} exited with {return_code}\n\n{session.transcript()}"
            )
        return session.transcript()
    finally:
        session.close()
        assert_no_process_group(process_group)


def test_moonbit_flow(
    moon: Path,
    env: dict[str, str],
    timeout: float,
) -> None:
    def drive(session: PtyProcess) -> None:
        session.send("p input")
        session.expect("Cannot inspect a variable while the debugger is Ready.")
        session.expect("(moondbg) ")
        session.send("continue")
        session.expect("Cannot continue execution while the debugger is Ready.")
        session.expect("(moondbg) ")
        session.send("break main/main.mbt:4")
        session.expect("Breakpoint 1 pending")
        session.expect("(moondbg) ")
        session.send("break main/main.mbt:5")
        session.expect("Breakpoint 2 pending")
        session.expect("(moondbg) ")
        session.send("run")
        session.expect("Breakpoint 1 verified")
        session.expect("Breakpoint 2 verified")
        session.expect("Stopped (")
        session.expect("(moondbg) ")
        session.send("p input")
        session.expect("input: int = 41")
        session.expect("(moondbg) ")
        session.send("p answer")
        session.expect("answer: int = 42")
        session.expect("(moondbg) ")
        session.send("continue")
        session.expect("42")
        session.expect("Stopped (")
        session.expect("(moondbg) ")
        session.send("p answer")
        session.expect("answer: int = 42")
        session.expect("(moondbg) ")
        session.send("continue")
        session.expect("83")
        session.expect("Process exited normally (code 0).")
        session.expect("(moondbg) ")
        session.send("run")
        session.expect("Breakpoint 1 verified")
        session.expect("Breakpoint 2 verified")
        session.expect("Stopped (")
        session.expect("(moondbg) ")
        session.send("run")
        session.expect("Restarting program.")
        session.expect("Breakpoint 1 verified")
        session.expect("Breakpoint 2 verified")
        session.expect("Stopped (")
        session.expect("(moondbg) ")
        session.send("quit")
        session.expect("Debugger exited.")

    transcript = run_session(
        [str(moon), "debug", "main"],
        cwd=DWARF_PROBE,
        env=env,
        timeout=timeout,
        drive=drive,
    )
    for expected in ("42\n", "83\n"):
        if expected not in transcript:
            raise ReplError(f"missing debuggee output {expected!r}\n\n{transcript}")
    if "exited with status =" in transcript:
        raise ReplError(f"raw lldb process status leaked to the REPL\n\n{transcript}")


def compile_exit_probe(directory: Path) -> Path:
    compiler = os.environ.get("CC") or shutil.which("cc")
    if not compiler:
        raise ReplError("cc was not found")
    executable = directory / "exit-probe"
    subprocess.run(
        [compiler, str(EXIT_PROBE), "-o", str(executable)],
        check=True,
    )
    return executable


def test_abnormal_exit(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
) -> None:
    def drive(session: PtyProcess) -> None:
        session.send("run")
        session.expect("c-exit-probe")
        session.expect("Process exited with code 7.")
        session.expect("(moondbg) ")
        session.send("quit")
        session.expect("Debugger exited.")

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=env,
        timeout=timeout,
        drive=drive,
    )


def test_quit(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
) -> None:
    def drive(session: PtyProcess) -> None:
        session.send("quit")
        session.expect("Debugger exited.")

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=env,
        timeout=timeout,
        drive=drive,
    )


def test_adapter_failure(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
) -> None:
    failing_adapter = shutil.which("false")
    if not failing_adapter:
        raise ReplError("false was not found")
    failing_env = dict(env)
    failing_env["MOONDBG_LLDB_DAP"] = failing_adapter

    def drive(session: PtyProcess) -> None:
        session.send("run")
        session.expect("moondbg: debugger adapter failed:")
        session.expect("(moondbg) ")
        session.send("quit")
        session.expect("Debugger exited.")

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=failing_env,
        timeout=timeout,
        drive=drive,
    )


def read_trace(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines()]


def wait_for_trace(path: Path, predicate, timeout: float) -> list[dict]:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            records = read_trace(path)
        except (FileNotFoundError, json.JSONDecodeError):
            time.sleep(0.02)
            continue
        if predicate(records):
            return records
        time.sleep(0.02)
    records = read_trace(path) if path.exists() else []
    raise ReplError(f"timed out waiting for fake adapter trace\n\n{records!r}")


def traced_commands(path: Path) -> list[str]:
    return [
        record["command"]
        for record in read_trace(path)
        if record["kind"] == "request"
    ]


def test_fake_adapter_flow(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
    directory: Path,
) -> None:
    initialize_delay = 1.8
    trace = directory / "fake-adapter-flow.jsonl"
    fake_env = dict(env)
    fake_env.update(
        {
            "MOONDBG_LLDB_DAP": str(FAKE_DAP),
            "MOONDBG_FAKE_DAP_INITIALIZE_DELAY_MS": str(
                int(initialize_delay * 1000)
            ),
            "MOONDBG_FAKE_DAP_SOURCE": str(EXIT_PROBE),
            "MOONDBG_FAKE_DAP_SOURCE_LINE": "1",
            "MOONDBG_FAKE_DAP_TRACE": str(trace),
            "MOONDBG_FAKE_DAP_DUPLICATE_TERMINATED": "1",
            "MOONDBG_FAKE_DAP_LATE_OUTPUT": "1",
        }
    )

    def drive(session: PtyProcess) -> None:
        if session.initial_prompt_elapsed >= initialize_delay / 2:
            raise ReplError(
                "initial prompt waited for fake adapter initialization: "
                f"{session.initial_prompt_elapsed:.3f}s"
            )
        help_started = time.monotonic()
        session.send("help")
        session.expect("Commands:")
        session.expect("(moondbg) ")
        help_elapsed = time.monotonic() - help_started
        if help_elapsed >= initialize_delay / 2:
            raise ReplError(
                f"local help command waited for adapter: {help_elapsed:.3f}s"
            )
        session.send(f"break {EXIT_PROBE}:1")
        session.expect("Breakpoint 1 pending")
        session.expect("(moondbg) ")
        run_started = time.monotonic()
        session.send("run")
        session.expect("Breakpoint 1 verified")
        run_elapsed = time.monotonic() - run_started
        if run_elapsed < initialize_delay / 3:
            raise ReplError(
                "run did not wait for the in-flight adapter preparation: "
                f"{run_elapsed:.3f}s"
            )
        session.expect("Stopped (breakpoint) in fake.main")
        session.expect("(moondbg) ")
        session.send("p answer")
        session.expect("answer: int = 42")
        session.expect("(moondbg) ")
        session.send("continue")
        session.expect("fake-output")
        session.expect("Process exited normally (code 0).")
        session.expect("(moondbg) ")
        session.send("run")
        session.expect("Breakpoint 1 verified")
        session.expect("Stopped (breakpoint) in fake.main")
        session.expect("(moondbg) ")
        session.send("run")
        session.expect("Restarting program.")
        session.expect("Breakpoint 1 verified")
        session.expect("Stopped (breakpoint) in fake.main")
        session.expect("(moondbg) ")
        session.send("p answer")
        session.expect("answer: int = 42")
        session.expect("(moondbg) ")
        session.send("quit")
        session.expect("Debugger exited.")

    transcript = run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=fake_env,
        timeout=timeout,
        drive=drive,
    )
    records = read_trace(trace)
    adapter_pids = [
        record["pid"] for record in records if record["kind"] == "start"
    ]
    if len(adapter_pids) != 3 or len(set(adapter_pids)) != 3:
        raise ReplError(
            f"expected three distinct fake adapters, got {adapter_pids!r}"
        )
    commands_by_adapter = [
        [
            record["command"]
            for record in records
            if record["kind"] == "request" and record["pid"] == pid
        ]
        for pid in adapter_pids
    ]
    expected_by_adapter = [
        [
            "initialize",
            "launch",
            "setBreakpoints",
            "configurationDone",
            "stackTrace",
            "scopes",
            "variables",
            "continue",
        ],
        [
            "initialize",
            "launch",
            "setBreakpoints",
            "configurationDone",
            "stackTrace",
            "disconnect",
        ],
        [
            "initialize",
            "launch",
            "setBreakpoints",
            "configurationDone",
            "stackTrace",
            "scopes",
            "variables",
            "disconnect",
        ],
    ]
    if commands_by_adapter != expected_by_adapter:
        raise ReplError(
            "unexpected requests across repeated fake executions: "
            f"{commands_by_adapter!r}"
        )
    if transcript.count("Breakpoint 1 verified") != 3:
        raise ReplError(
            "logical breakpoint was not replayed with stable id three times\n\n"
            + transcript
        )
    if transcript.count("Process exited normally (code 0).") != 1:
        raise ReplError("exit feedback was duplicated\n\n" + transcript)
    if "late-output-should-not-render" in transcript:
        raise ReplError("a late event leaked across executions\n\n" + transcript)


def test_fake_stepping_commands(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
    directory: Path,
) -> None:
    trace = directory / "fake-stepping-commands.jsonl"
    fake_env = dict(env)
    fake_env.update(
        {
            "MOONDBG_LLDB_DAP": str(FAKE_DAP),
            "MOONDBG_FAKE_DAP_SOURCE": str(EXIT_PROBE),
            "MOONDBG_FAKE_DAP_SOURCE_LINE": "1",
            "MOONDBG_FAKE_DAP_TRACE": str(trace),
        }
    )

    def drive(session: PtyProcess) -> None:
        session.send("help")
        session.expect("next                 n")
        session.expect("step                 s")
        session.expect("finish               fin")
        session.expect("(moondbg) ")
        session.send("next")
        session.expect("Cannot step over while the debugger is Ready.")
        session.expect("(moondbg) ")
        session.send("step")
        session.expect("Cannot step into while the debugger is Ready.")
        session.expect("(moondbg) ")
        session.send("finish")
        session.expect("Cannot step out while the debugger is Ready.")
        session.expect("(moondbg) ")
        session.send("run")
        session.expect("Stopped (breakpoint) in fake.main")
        session.expect("(moondbg) ")
        for command in ("n", "s", "fin"):
            session.send(command)
            session.expect("Stopped (step) in fake.main")
            session.expect("(moondbg) ")
        session.send("quit")
        session.expect("Debugger exited.")

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=fake_env,
        timeout=timeout,
        drive=drive,
    )
    commands = traced_commands(trace)
    for command in ("next", "stepIn", "stepOut"):
        if commands.count(command) != 1:
            raise ReplError(
                f"REPL did not dispatch exactly one {command} request: {commands!r}"
            )


def test_fake_adapter_failure(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
    directory: Path,
) -> None:
    trace = directory / "fake-adapter-failure.jsonl"
    fake_env = dict(env)
    fake_env.update(
        {
            "MOONDBG_LLDB_DAP": str(FAKE_DAP),
            "MOONDBG_FAKE_DAP_MODE": "exit-before-initialize-response",
            "MOONDBG_FAKE_DAP_TRACE": str(trace),
        }
    )

    def drive(session: PtyProcess) -> None:
        session.send("run")
        session.expect("moondbg: debugger adapter failed:")
        session.expect("(moondbg) ")
        session.send("quit")
        session.expect("Debugger exited.")

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=fake_env,
        timeout=timeout,
        drive=drive,
    )
    commands = traced_commands(trace)
    if not commands or any(command != "initialize" for command in commands):
        raise ReplError(
            f"failure adapter received unexpected requests: {commands!r}"
        )


def test_fake_preparation_failure_recovery(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
    directory: Path,
) -> None:
    trace = directory / "fake-adapter-preparation-recovery.jsonl"
    marker = directory / "fake-adapter-preparation-recovery.once"
    fake_env = dict(env)
    fake_env.update(
        {
            "MOONDBG_LLDB_DAP": str(FAKE_DAP),
            "MOONDBG_FAKE_DAP_FAIL_ONCE_COMMAND": "initialize",
            "MOONDBG_FAKE_DAP_FAIL_ONCE_MARKER": str(marker),
            "MOONDBG_FAKE_DAP_SOURCE": str(EXIT_PROBE),
            "MOONDBG_FAKE_DAP_SOURCE_LINE": "1",
            "MOONDBG_FAKE_DAP_TRACE": str(trace),
        }
    )

    def drive(session: PtyProcess) -> None:
        session.send("run")
        session.expect("moondbg: debugger adapter failed:")
        session.expect("(moondbg) ")
        records = wait_for_trace(
            trace,
            lambda items: sum(
                1
                for item in items
                if item["kind"] == "request"
                and item.get("command") == "initialize"
            )
            >= 2,
            timeout,
        )
        commands = [
            item["command"] for item in records if item["kind"] == "request"
        ]
        if "launch" in commands:
            raise ReplError("preparation failure silently launched the program")
        session.send("help")
        session.expect("Commands:")
        session.expect("(moondbg) ")
        session.send("run")
        session.expect("Stopped (breakpoint) in fake.main")
        session.expect("(moondbg) ")
        session.send("quit")
        session.expect("Debugger exited.")

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=fake_env,
        timeout=timeout,
        drive=drive,
    )
    records = read_trace(trace)
    adapter_pids = {
        item["pid"]
        for item in records
        if item["kind"] == "request" and item.get("command") == "initialize"
    }
    if len(adapter_pids) != 2 or traced_commands(trace).count("launch") != 1:
        raise ReplError(
            "preparation recovery did not require exactly one explicit run: "
            f"{records!r}"
        )


def test_fake_running_failure_recovery(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
    directory: Path,
) -> None:
    trace = directory / "fake-adapter-running-recovery.jsonl"
    marker = directory / "fake-adapter-running-recovery.once"
    fake_env = dict(env)
    fake_env.update(
        {
            "MOONDBG_LLDB_DAP": str(FAKE_DAP),
            "MOONDBG_FAKE_DAP_FAIL_ONCE_COMMAND": "variables",
            "MOONDBG_FAKE_DAP_FAIL_ONCE_MARKER": str(marker),
            "MOONDBG_FAKE_DAP_SOURCE": str(EXIT_PROBE),
            "MOONDBG_FAKE_DAP_SOURCE_LINE": "1",
            "MOONDBG_FAKE_DAP_TRACE": str(trace),
        }
    )

    def drive(session: PtyProcess) -> None:
        session.send("run")
        session.expect("Stopped (breakpoint) in fake.main")
        session.expect("(moondbg) ")
        session.send("p answer")
        session.expect("moondbg: debugger adapter failed:")
        session.expect("(moondbg) ")
        records = wait_for_trace(
            trace,
            lambda items: sum(
                1
                for item in items
                if item["kind"] == "request"
                and item.get("command") == "initialize"
            )
            >= 2,
            timeout,
        )
        commands = [
            item["command"] for item in records if item["kind"] == "request"
        ]
        if commands.count("launch") != 1:
            raise ReplError("running failure silently relaunched the program")
        session.send("p answer")
        session.expect("Cannot inspect a variable while the debugger is Ready.")
        session.expect("(moondbg) ")
        session.send("run")
        session.expect("Stopped (breakpoint) in fake.main")
        session.expect("(moondbg) ")
        session.send("p answer")
        session.expect("answer: int = 42")
        session.expect("(moondbg) ")
        session.send("quit")
        session.expect("Debugger exited.")

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=fake_env,
        timeout=timeout,
        drive=drive,
    )
    records = read_trace(trace)
    adapter_pids = {
        item["pid"]
        for item in records
        if item["kind"] == "request" and item.get("command") == "initialize"
    }
    if len(adapter_pids) != 2 or traced_commands(trace).count("launch") != 2:
        raise ReplError(f"running failure recovery was not isolated: {records!r}")


def test_fake_continue_failure_recovery(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
    directory: Path,
) -> None:
    trace = directory / "fake-adapter-continue-recovery.jsonl"
    marker = directory / "fake-adapter-continue-recovery.once"
    fake_env = dict(env)
    fake_env.update(
        {
            "MOONDBG_LLDB_DAP": str(FAKE_DAP),
            "MOONDBG_FAKE_DAP_FAIL_ONCE_COMMAND": "continue",
            "MOONDBG_FAKE_DAP_FAIL_ONCE_MARKER": str(marker),
            "MOONDBG_FAKE_DAP_SOURCE": str(EXIT_PROBE),
            "MOONDBG_FAKE_DAP_SOURCE_LINE": "1",
            "MOONDBG_FAKE_DAP_TRACE": str(trace),
        }
    )

    def drive(session: PtyProcess) -> None:
        session.send("run")
        session.expect("Stopped (breakpoint) in fake.main")
        session.expect("(moondbg) ")
        session.send("continue")
        session.expect("moondbg: debugger adapter failed:")
        session.expect("(moondbg) ")
        records = wait_for_trace(
            trace,
            lambda items: sum(
                1
                for item in items
                if item["kind"] == "request"
                and item.get("command") == "initialize"
            )
            >= 2,
            timeout,
        )
        commands = [
            item["command"] for item in records if item["kind"] == "request"
        ]
        if commands.count("launch") != 1:
            raise ReplError("continue failure silently relaunched the program")
        session.send("p answer")
        session.expect("Cannot inspect a variable while the debugger is Ready.")
        session.expect("(moondbg) ")
        session.send("run")
        session.expect("Stopped (breakpoint) in fake.main")
        session.expect("(moondbg) ")
        session.send("quit")
        session.expect("Debugger exited.")

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=fake_env,
        timeout=timeout,
        drive=drive,
    )
    records = read_trace(trace)
    adapter_pids = {
        item["pid"]
        for item in records
        if item["kind"] == "request" and item.get("command") == "initialize"
    }
    if len(adapter_pids) != 2 or traced_commands(trace).count("launch") != 2:
        raise ReplError(f"continue failure recovery was not isolated: {records!r}")


def test_fake_preparation_timeout(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
    directory: Path,
) -> None:
    trace = directory / "fake-adapter-timeout.jsonl"
    fake_env = dict(env)
    fake_env.update(
        {
            "MOONDBG_LLDB_DAP": str(FAKE_DAP),
            "MOONDBG_ADAPTER_TIMEOUT_MS": "100",
            "MOONDBG_FAKE_DAP_INITIALIZE_DELAY_MS": "500",
            "MOONDBG_FAKE_DAP_TRACE": str(trace),
        }
    )

    def drive(session: PtyProcess) -> None:
        session.send("run")
        session.expect("lldb-dap initialize timed out after 100 ms")
        session.expect("(moondbg) ")
        session.send("help")
        session.expect("Commands:")
        session.expect("(moondbg) ")
        session.send("quit")
        session.expect("Debugger exited.")

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=fake_env,
        timeout=timeout,
        drive=drive,
    )
    commands = traced_commands(trace)
    if "launch" in commands:
        raise ReplError(f"timed-out preparation launched the program: {commands!r}")


def test_readline_interrupt_and_eof(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
    directory: Path,
) -> None:
    interrupt_env = dict(env)
    interrupt_env.update(
        {
            "MOONDBG_LLDB_DAP": str(FAKE_DAP),
            "MOONDBG_FAKE_DAP_TRACE": str(directory / "interrupt.jsonl"),
        }
    )

    def interrupt(session: PtyProcess) -> None:
        session.send_bytes(b"\x03")
        session.expect("(moondbg) ")
        session.send("quit")
        session.expect("Debugger exited.")

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=interrupt_env,
        timeout=timeout,
        drive=interrupt,
    )

    eof_env = dict(env)
    eof_env.update(
        {
            "MOONDBG_LLDB_DAP": str(FAKE_DAP),
            "MOONDBG_FAKE_DAP_TRACE": str(directory / "eof.jsonl"),
        }
    )

    def eof(session: PtyProcess) -> None:
        session.send_bytes(b"\x04")
        session.expect("Debugger exited.")

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=eof_env,
        timeout=timeout,
        drive=eof,
    )


def test_quit_during_fake_adapter_preparation(
    moondbg: Path,
    executable: Path,
    env: dict[str, str],
    timeout: float,
    directory: Path,
) -> None:
    trace = directory / "fake-adapter-early-quit.jsonl"
    initialize_delay = 5.0
    fake_env = dict(env)
    fake_env.update(
        {
            "MOONDBG_LLDB_DAP": str(FAKE_DAP),
            "MOONDBG_FAKE_DAP_INITIALIZE_DELAY_MS": str(
                int(initialize_delay * 1000)
            ),
            "MOONDBG_FAKE_DAP_TRACE": str(trace),
        }
    )

    def drive(session: PtyProcess) -> None:
        if session.initial_prompt_elapsed >= initialize_delay / 2:
            raise ReplError(
                "initial prompt waited during early-quit test: "
                f"{session.initial_prompt_elapsed:.3f}s"
            )
        quit_started = time.monotonic()
        session.send("quit")
        session.expect("Debugger exited.")
        quit_elapsed = time.monotonic() - quit_started
        if quit_elapsed >= initialize_delay / 2:
            raise ReplError(
                f"quit waited for adapter initialization: {quit_elapsed:.3f}s"
            )

    run_session(
        [str(moondbg), str(executable)],
        cwd=ROOT,
        env=fake_env,
        timeout=timeout,
        drive=drive,
    )
    if trace.exists():
        commands = traced_commands(trace)
        if commands not in ([], ["initialize"]):
            raise ReplError(
                f"early-quit adapter received unexpected requests: {commands!r}"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=float, default=15)
    parser.add_argument("--skip-build", action="store_true")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--fake-only", action="store_true")
    selection.add_argument("--real-only", action="store_true")
    args = parser.parse_args()
    try:
        moon, moondbg = require_development_environment()
        env = dict(os.environ)
        env.setdefault("TERM", "xterm-256color")
        if not args.skip_build:
            subprocess.run([str(moon), "build"], cwd=ROOT, env=env, check=True)
        with tempfile.TemporaryDirectory(prefix="moondbg-e2e-") as directory:
            test_directory = Path(directory)
            executable = compile_exit_probe(test_directory)
            if not args.real_only:
                test_fake_adapter_flow(
                    moondbg, executable, env, args.timeout, test_directory
                )
                test_fake_stepping_commands(
                    moondbg, executable, env, args.timeout, test_directory
                )
                test_fake_adapter_failure(
                    moondbg, executable, env, args.timeout, test_directory
                )
                test_fake_preparation_failure_recovery(
                    moondbg, executable, env, args.timeout, test_directory
                )
                test_fake_running_failure_recovery(
                    moondbg, executable, env, args.timeout, test_directory
                )
                test_fake_continue_failure_recovery(
                    moondbg, executable, env, args.timeout, test_directory
                )
                test_fake_preparation_timeout(
                    moondbg, executable, env, args.timeout, test_directory
                )
                test_quit_during_fake_adapter_preparation(
                    moondbg, executable, env, args.timeout, test_directory
                )
                test_readline_interrupt_and_eof(
                    moondbg, executable, env, args.timeout, test_directory
                )
            if not args.fake_only:
                test_moonbit_flow(moon, env, args.timeout)
                test_abnormal_exit(moondbg, executable, env, args.timeout)
                test_quit(moondbg, executable, env, args.timeout)
                test_adapter_failure(moondbg, executable, env, args.timeout)
    except (OSError, ReplError, subprocess.CalledProcessError) as error:
        print(f"repl e2e failed: {error}", file=sys.stderr)
        return 1
    if args.fake_only:
        print(
            "repl e2e passed: prompt prewarm, fake adapter flow, stepping, "
            "early quit, failure recovery, timeout, terminal controls"
        )
    elif args.real_only:
        print("repl e2e passed: MoonBit flow, abnormal exit, quit, adapter failure")
    else:
        print(
            "repl e2e passed: fake adapter, MoonBit flow, abnormal exit, quit, "
            "adapter failure"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
