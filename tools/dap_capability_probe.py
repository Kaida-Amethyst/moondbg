#!/usr/bin/env python3
"""Probe the lldb-dap capabilities needed by T-02/P1.

This is a development diagnostic, not part of moondbg's product protocol. It
keeps the raw DAP exercise independent from the DebugSession implementation
that P2 will replace.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import time
from typing import Any


class ProbeError(RuntimeError):
    pass


def discover_adapter(explicit: str | None) -> str:
    if explicit:
        return explicit
    override = os.environ.get("MOONDBG_LLDB_DAP")
    if override:
        return override
    if sys.platform == "darwin":
        discovered = subprocess.run(
            ["xcrun", "--find", "lldb-dap"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
        if discovered.returncode == 0 and discovered.stdout.strip():
            return discovered.stdout.strip()
    adapter = shutil.which("lldb-dap")
    if adapter:
        return adapter
    raise ProbeError("could not locate lldb-dap")


def marker_line(source: Path, marker: str) -> int:
    matches = [
        line_number
        for line_number, line in enumerate(source.read_text().splitlines(), 1)
        if marker in line
    ]
    if len(matches) != 1:
        raise ProbeError(
            f"expected exactly one {marker!r} marker in {source}, found {len(matches)}"
        )
    return matches[0]


def parse_expected_variable(value: str) -> tuple[str, str]:
    name, separator, expected = value.partition("=")
    if not separator or not name:
        raise argparse.ArgumentTypeError("expected NAME=VALUE")
    return name, expected


class DapClient:
    def __init__(self, adapter: str, timeout: float) -> None:
        self.adapter = adapter
        self.timeout = timeout
        self.process = subprocess.Popen(
            [adapter],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if self.process.stdin is None or self.process.stdout is None:
            raise ProbeError("failed to create lldb-dap pipes")
        self.stdin = self.process.stdin
        self.stdout = self.process.stdout
        self.buffer = bytearray()
        self.next_seq = 1
        self.responses: dict[int, dict[str, Any]] = {}
        self.events: list[dict[str, Any]] = []
        self.event_history: list[dict[str, Any]] = []
        self.message_order: list[str] = []

    def send_request(self, command: str, arguments: dict[str, Any]) -> int:
        seq = self.next_seq
        self.next_seq += 1
        body = json.dumps(
            {
                "seq": seq,
                "type": "request",
                "command": command,
                "arguments": arguments,
            },
            separators=(",", ":"),
        ).encode()
        self.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode())
        self.stdin.write(body)
        self.stdin.flush()
        return seq

    def _read_more(self, deadline: float) -> None:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ProbeError("timed out waiting for lldb-dap")
        ready, _, _ = select.select([self.stdout], [], [], remaining)
        if not ready:
            raise ProbeError("timed out waiting for lldb-dap")
        chunk = os.read(self.stdout.fileno(), 65536)
        if not chunk:
            raise ProbeError("lldb-dap closed its stdout")
        self.buffer.extend(chunk)

    def _read_message(self) -> dict[str, Any]:
        deadline = time.monotonic() + self.timeout
        separator = b"\r\n\r\n"
        while separator not in self.buffer:
            self._read_more(deadline)
        header, _, remaining = self.buffer.partition(separator)
        self.buffer = bytearray(remaining)
        content_length: int | None = None
        for raw_line in header.split(b"\r\n"):
            name, found, value = raw_line.partition(b":")
            if found and name.strip().lower() == b"content-length":
                content_length = int(value.strip())
        if content_length is None:
            raise ProbeError("DAP frame is missing Content-Length")
        while len(self.buffer) < content_length:
            self._read_more(deadline)
        body = bytes(self.buffer[:content_length])
        del self.buffer[:content_length]
        message = json.loads(body)
        if not isinstance(message, dict):
            raise ProbeError("DAP message is not a JSON object")
        return message

    def receive(self) -> dict[str, Any]:
        message = self._read_message()
        message_type = message.get("type")
        if message_type == "response":
            request_seq = message.get("request_seq")
            if not isinstance(request_seq, int):
                raise ProbeError("DAP response has no integer request_seq")
            self.responses[request_seq] = message
            outcome = "ok" if message.get("success") else "failed"
            self.message_order.append(
                f"response:{message.get('command', '?')}:{outcome}#{request_seq}"
            )
        elif message_type == "event":
            self.events.append(message)
            self.event_history.append(message)
            self.message_order.append(f"event:{message.get('event', '?')}")
        elif message_type == "request":
            self.message_order.append(f"request:{message.get('command', '?')}")
            raise ProbeError(
                f"adapter request is unsupported by the probe: {message.get('command')!r}"
            )
        else:
            raise ProbeError(f"unknown DAP message type: {message_type!r}")
        return message

    def wait_response(self, request_seq: int) -> dict[str, Any]:
        while request_seq not in self.responses:
            self.receive()
        return self.responses.pop(request_seq)

    def require_response(self, request_seq: int, command: str) -> dict[str, Any]:
        response = self.wait_response(request_seq)
        if not response.get("success"):
            raise ProbeError(
                f"{command} failed: {response.get('message', 'no adapter message')}"
            )
        return response

    def wait_event(self, *names: str) -> dict[str, Any]:
        expected = set(names)
        while True:
            for index, event in enumerate(self.events):
                if event.get("event") in expected:
                    return self.events.pop(index)
            self.receive()

    def try_wait_event(self, timeout: float, *names: str) -> dict[str, Any] | None:
        original_timeout = self.timeout
        self.timeout = timeout
        try:
            return self.wait_event(*names)
        except ProbeError as error:
            if "timed out" in str(error) or "closed its stdout" in str(error):
                return None
            raise
        finally:
            self.timeout = original_timeout

    def request(self, command: str, arguments: dict[str, Any]) -> dict[str, Any]:
        seq = self.send_request(command, arguments)
        return self.require_response(seq, command)

    def shutdown(self) -> str:
        if self.process.poll() is None:
            try:
                seq = self.send_request(
                    "disconnect", {"terminateDebuggee": True}
                )
                self.require_response(seq, "disconnect")
            except (BrokenPipeError, ProbeError):
                pass
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=2)
        stderr = b""
        if self.process.stderr is not None:
            stderr = self.process.stderr.read()
        return stderr.decode(errors="replace")


def response_body(response: dict[str, Any]) -> dict[str, Any]:
    body = response.get("body", {})
    return body if isinstance(body, dict) else {}


def event_body(event: dict[str, Any]) -> dict[str, Any]:
    body = event.get("body", {})
    return body if isinstance(body, dict) else {}


def source_path(frame: dict[str, Any]) -> str | None:
    source = frame.get("source")
    if not isinstance(source, dict):
        return None
    path = source.get("path")
    return path if isinstance(path, str) else None


def same_path(left: str | None, right: Path) -> bool:
    if left is None:
        return False
    try:
        return Path(left).resolve() == right.resolve()
    except OSError:
        return False


def summarize_variable(variable: dict[str, Any] | None) -> dict[str, Any] | None:
    if variable is None:
        return None
    return {
        "name": variable.get("name"),
        "type": variable.get("type"),
        "value": variable.get("value"),
        "variablesReference": variable.get("variablesReference"),
    }


def run_probe(args: argparse.Namespace) -> tuple[dict[str, Any], bool]:
    executable = Path(args.executable).resolve(strict=True)
    source = Path(args.source).resolve(strict=True)
    line = args.line if args.line is not None else marker_line(source, args.marker)
    adapter = discover_adapter(args.adapter)
    expected_variables = dict(args.expect_variable)
    report: dict[str, Any] = {
        "adapter": adapter,
        "executable": str(executable),
        "source": str(source),
        "breakpointLine": line,
        "expectedVariables": expected_variables,
    }
    client = DapClient(adapter, args.timeout)
    try:
        initialize = client.request(
            "initialize",
            {
                "clientID": "moondbg-dwarf-probe",
                "clientName": "moondbg DWARF probe",
                "adapterID": "lldb-dap",
                "pathFormat": "path",
                "linesStartAt1": True,
                "columnsStartAt1": True,
                "supportsVariableType": True,
                "supportsRunInTerminalRequest": False,
            },
        )
        report["initializeCapabilities"] = response_body(initialize)

        launch_seq = client.send_request(
            "launch", {"program": str(executable), "stopOnEntry": False}
        )
        client.wait_event("initialized")
        breakpoint_response = client.request(
            "setBreakpoints",
            {
                "source": {"name": source.name, "path": str(source)},
                "breakpoints": [{"line": line}],
                "sourceModified": False,
            },
        )
        breakpoints = response_body(breakpoint_response).get("breakpoints", [])
        breakpoint = breakpoints[0] if breakpoints else {}
        report["breakpoint"] = breakpoint
        client.request("configurationDone", {})

        stable_event = client.wait_event("stopped", "exited", "terminated")
        report["firstStableEvent"] = {
            "event": stable_event.get("event"),
            "body": event_body(stable_event),
        }
        client.require_response(launch_seq, "launch")

        selected_frame: dict[str, Any] | None = None
        variables_by_name: dict[str, dict[str, Any]] = {}
        stopped = stable_event.get("event") == "stopped"
        if stopped:
            stopped_body = event_body(stable_event)
            thread_id = stopped_body.get("threadId")
            if not isinstance(thread_id, int):
                threads = response_body(client.request("threads", {})).get(
                    "threads", []
                )
                if threads and isinstance(threads[0], dict):
                    thread_id = threads[0].get("id")
            if not isinstance(thread_id, int):
                raise ProbeError("stopped event did not identify a usable thread")
            report["threadId"] = thread_id
            stack = response_body(
                client.request(
                    "stackTrace",
                    {"threadId": thread_id, "startFrame": 0, "levels": 20},
                )
            ).get("stackFrames", [])
            frames = [frame for frame in stack if isinstance(frame, dict)]
            selected_frame = next(
                (frame for frame in frames if same_path(source_path(frame), source)),
                frames[0] if frames else None,
            )
            report["stackFrames"] = frames
            report["selectedFrame"] = selected_frame
            if selected_frame is not None:
                frame_id = selected_frame.get("id")
                if not isinstance(frame_id, int):
                    raise ProbeError("selected stack frame has no integer id")
                scopes = response_body(
                    client.request("scopes", {"frameId": frame_id})
                ).get("scopes", [])
                report["scopes"] = scopes
                for scope in scopes:
                    if not isinstance(scope, dict):
                        continue
                    reference = scope.get("variablesReference")
                    if not isinstance(reference, int) or reference <= 0:
                        continue
                    variables = response_body(
                        client.request(
                            "variables", {"variablesReference": reference}
                        )
                    ).get("variables", [])
                    for variable in variables:
                        if isinstance(variable, dict) and isinstance(
                            variable.get("name"), str
                        ):
                            variables_by_name.setdefault(variable["name"], variable)
            report["variables"] = {
                name: summarize_variable(variables_by_name.get(name))
                for name in expected_variables
            }

            continue_seq = client.send_request(
                "continue", {"threadId": thread_id, "singleThread": False}
            )
            client.require_response(continue_seq, "continue")
            exit_event = client.wait_event("exited", "terminated")
            report["exitEvent"] = {
                "event": exit_event.get("event"),
                "body": event_body(exit_event),
            }
            client.try_wait_event(2.0, "terminated")

        checks = {
            "breakpointVerified": breakpoint.get("verified") is True,
            "stoppedAtBreakpoint": stopped,
            "frameSourceMatches": selected_frame is not None
            and same_path(source_path(selected_frame), source),
            "frameLineMatches": selected_frame is not None
            and selected_frame.get("line") == line,
        }
        for name, expected_value in expected_variables.items():
            variable = variables_by_name.get(name)
            checks[f"variable:{name}:present"] = variable is not None
            checks[f"variable:{name}:type"] = variable is not None and bool(
                variable.get("type")
            )
            checks[f"variable:{name}:value"] = variable is not None and str(
                variable.get("value")
            ) == expected_value
        report["checks"] = checks
        report["allChecksPassed"] = all(checks.values())
        return report, bool(report["allChecksPassed"])
    finally:
        report["messageOrder"] = client.message_order
        report["adapterStderr"] = client.shutdown()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Probe MoonBit DWARF through a real lldb-dap session."
    )
    parser.add_argument("executable")
    parser.add_argument("source")
    parser.add_argument("--adapter")
    parser.add_argument("--line", type=int)
    parser.add_argument("--marker", default="MOONDBG_BREAKPOINT")
    parser.add_argument(
        "--expect-variable",
        action="append",
        default=[],
        type=parse_expected_variable,
        metavar="NAME=VALUE",
    )
    parser.add_argument("--timeout", type=float, default=10.0)
    args = parser.parse_args()
    try:
        report, succeeded = run_probe(args)
    except (OSError, ValueError, ProbeError) as error:
        json.dump(
            {"allChecksPassed": False, "fatalError": str(error)},
            sys.stdout,
            indent=2,
            ensure_ascii=False,
        )
        sys.stdout.write("\n")
        return 2
    json.dump(report, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0 if succeeded else 2


if __name__ == "__main__":
    raise SystemExit(main())
