#!/usr/bin/env python3
"""Deterministic DAP adapter used by moondbg lifecycle tests."""

from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import time
from typing import Any, BinaryIO


class ProtocolError(RuntimeError):
    pass


class FakeAdapter:
    def __init__(self) -> None:
        self.input = sys.stdin.buffer
        self.output = sys.stdout.buffer
        self.next_seq = 1
        self.mode = os.environ.get("MOONDBG_FAKE_DAP_MODE", "normal")
        self.launch_order = os.environ.get(
            "MOONDBG_FAKE_DAP_LAUNCH_ORDER", "response-first"
        )
        self.initialize_delay = (
            int(os.environ.get("MOONDBG_FAKE_DAP_INITIALIZE_DELAY_MS", "0"))
            / 1000
        )
        self.fail_once_command = os.environ.get(
            "MOONDBG_FAKE_DAP_FAIL_ONCE_COMMAND"
        )
        marker_value = os.environ.get("MOONDBG_FAKE_DAP_FAIL_ONCE_MARKER")
        self.fail_once_marker = Path(marker_value) if marker_value else None
        self.forced_failure = False
        self.duplicate_terminated = (
            os.environ.get("MOONDBG_FAKE_DAP_DUPLICATE_TERMINATED") == "1"
        )
        self.late_output = os.environ.get("MOONDBG_FAKE_DAP_LATE_OUTPUT") == "1"
        self.thread_id = int(os.environ.get("MOONDBG_FAKE_DAP_THREAD_ID", "1"))
        self.step_outcome = os.environ.get(
            "MOONDBG_FAKE_DAP_STEP_OUTCOME", "stopped"
        )
        if self.step_outcome not in {
            "stopped",
            "exited",
            "terminated",
            "adapter-failure",
        }:
            raise ProtocolError(
                "MOONDBG_FAKE_DAP_STEP_OUTCOME must be stopped, exited, "
                "terminated, or adapter-failure"
            )
        self.step_exit_code = int(
            os.environ.get("MOONDBG_FAKE_DAP_STEP_EXIT_CODE", "0")
        )
        self.source = os.environ.get("MOONDBG_FAKE_DAP_SOURCE", __file__)
        self.source_line = int(os.environ.get("MOONDBG_FAKE_DAP_SOURCE_LINE", "1"))
        trace_value = os.environ.get("MOONDBG_FAKE_DAP_TRACE")
        self.trace_path = Path(trace_value) if trace_value else None

    def trace(self, kind: str, **fields: Any) -> None:
        if self.trace_path is None:
            return
        record = {"kind": kind, "pid": os.getpid(), **fields}
        with self.trace_path.open("a", encoding="utf-8") as trace_file:
            json.dump(record, trace_file, ensure_ascii=False, sort_keys=True)
            trace_file.write("\n")

    def send(self, message: dict[str, Any]) -> None:
        message = {"seq": self.next_seq, **message}
        self.next_seq += 1
        body = json.dumps(message, separators=(",", ":")).encode()
        self.output.write(f"Content-Length: {len(body)}\r\n\r\n".encode())
        self.output.write(body)
        self.output.flush()

    def should_fail_once(self, command: str) -> bool:
        if self.fail_once_command != command or self.fail_once_marker is None:
            return False
        try:
            with self.fail_once_marker.open("x", encoding="utf-8") as marker:
                marker.write(f"{os.getpid()}\n")
        except FileExistsError:
            return False
        self.forced_failure = True
        self.trace("forced-exit", point=command)
        return True

    def respond(
        self,
        request: dict[str, Any],
        body: dict[str, Any] | None = None,
    ) -> None:
        self.send(
            {
                "type": "response",
                "request_seq": request["seq"],
                "command": request["command"],
                "success": True,
                "body": body or {},
            }
        )

    def event(self, name: str, body: dict[str, Any] | None = None) -> None:
        self.send({"type": "event", "event": name, "body": body or {}})

    def reject(self, request: dict[str, Any], message: str) -> None:
        self.send(
            {
                "type": "response",
                "request_seq": request["seq"],
                "command": request["command"],
                "success": False,
                "message": message,
                "body": {},
            }
        )

    def handle_step(self, request: dict[str, Any]) -> bool:
        arguments = request.get("arguments")
        if not isinstance(arguments, dict):
            self.reject(request, "stepping request arguments must be an object")
            return True
        thread_id = arguments.get("threadId")
        if type(thread_id) is not int or thread_id != self.thread_id:
            self.reject(
                request,
                f"expected threadId {self.thread_id}, got {thread_id!r}",
            )
            return True
        granularity = arguments.get("granularity")
        if granularity not in (None, "statement", "line", "instruction"):
            self.reject(request, f"invalid stepping granularity {granularity!r}")
            return True
        if self.step_outcome == "adapter-failure":
            self.forced_failure = True
            self.trace("forced-exit", point=request["command"])
            return False
        self.respond(request)
        if self.step_outcome == "stopped":
            self.event("stopped", {"reason": "step", "threadId": self.thread_id})
        elif self.step_outcome == "exited":
            self.event("exited", {"exitCode": self.step_exit_code})
            self.event("terminated")
        else:
            self.event("terminated")
        return True

    def handle(self, request: dict[str, Any]) -> bool:
        command = request.get("command")
        if request.get("type") != "request" or not isinstance(command, str):
            raise ProtocolError(f"expected DAP request, got {request!r}")
        self.trace(
            "request",
            command=command,
            request_seq=request.get("seq"),
            arguments=request.get("arguments") or {},
        )
        if self.should_fail_once(command):
            return False
        if command == "initialize":
            if self.mode == "exit-before-initialize-response":
                self.trace("forced-exit", point="initialize")
                return False
            if self.initialize_delay > 0:
                time.sleep(self.initialize_delay)
            self.respond(
                request,
                {
                    "supportsConfigurationDoneRequest": True,
                    "supportsSteppingGranularity": True,
                    "supportsTerminateRequest": True,
                },
            )
        elif command == "launch":
            if self.launch_order == "initialized-first":
                self.event("initialized")
                self.respond(request)
            else:
                self.respond(request)
                self.event("initialized")
        elif command == "setBreakpoints":
            arguments = request.get("arguments") or {}
            requested = arguments.get("breakpoints") or []
            breakpoints = [
                {
                    "id": index + 100,
                    "verified": True,
                    "line": breakpoint.get("line", 1),
                }
                for index, breakpoint in enumerate(requested)
            ]
            self.respond(request, {"breakpoints": breakpoints})
        elif command == "configurationDone":
            self.respond(request)
            self.event(
                "stopped",
                {"reason": "breakpoint", "threadId": self.thread_id},
            )
        elif command == "threads":
            self.respond(
                request,
                {"threads": [{"id": self.thread_id, "name": "main"}]},
            )
        elif command == "stackTrace":
            self.respond(
                request,
                {
                    "stackFrames": [
                        {
                            "id": 10,
                            "name": "fake.main",
                            "source": {"path": self.source},
                            "line": self.source_line,
                            "column": 1,
                        }
                    ],
                    "totalFrames": 1,
                },
            )
        elif command == "scopes":
            self.respond(
                request,
                {
                    "scopes": [
                        {
                            "name": "Locals",
                            "presentationHint": "locals",
                            "variablesReference": 20,
                        }
                    ]
                },
            )
        elif command == "variables":
            self.respond(
                request,
                {
                    "variables": [
                        {
                            "name": "answer",
                            "type": "int",
                            "value": "42",
                            "variablesReference": 0,
                        }
                    ]
                },
            )
        elif command == "continue":
            self.respond(request, {"allThreadsContinued": True})
            self.event("output", {"category": "stdout", "output": "fake-output\n"})
            self.event("exited", {"exitCode": 0})
            self.event("terminated")
            if self.duplicate_terminated:
                self.event("terminated")
            if self.late_output:
                self.event(
                    "output",
                    {
                        "category": "stdout",
                        "output": "late-output-should-not-render\n",
                    },
                )
        elif command in ("next", "stepIn", "stepOut"):
            return self.handle_step(request)
        elif command == "disconnect":
            self.respond(request)
            return False
        else:
            self.reject(request, f"fake adapter does not support {command}")
        return True

    def run(self) -> int:
        self.trace("start", mode=self.mode)
        while (request := read_message(self.input)) is not None:
            if not self.handle(request):
                if self.mode == "exit-before-initialize-response":
                    exit_code = 17
                elif self.forced_failure:
                    exit_code = 18
                else:
                    exit_code = 0
                self.trace("stop", exit_code=exit_code)
                return exit_code
        self.trace("stop", exit_code=0)
        return 0


def read_message(stream: BinaryIO) -> dict[str, Any] | None:
    content_length: int | None = None
    while True:
        line = stream.readline()
        if not line:
            return None
        if line in (b"\n", b"\r\n"):
            break
        name, separator, value = line.decode().partition(":")
        if separator and name.lower() == "content-length":
            content_length = int(value.strip())
    if content_length is None:
        raise ProtocolError("missing Content-Length")
    body = stream.read(content_length)
    if len(body) != content_length:
        raise ProtocolError("unexpected EOF in DAP body")
    message = json.loads(body)
    if not isinstance(message, dict):
        raise ProtocolError("DAP message must be an object")
    return message


def main() -> int:
    try:
        return FakeAdapter().run()
    except (OSError, ProtocolError, ValueError, json.JSONDecodeError) as error:
        print(f"fake_dap: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
