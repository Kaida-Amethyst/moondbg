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

    def handle(self, request: dict[str, Any]) -> bool:
        command = request.get("command")
        if request.get("type") != "request" or not isinstance(command, str):
            raise ProtocolError(f"expected DAP request, got {request!r}")
        self.trace("request", command=command, request_seq=request.get("seq"))
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
            self.event("stopped", {"reason": "breakpoint", "threadId": 1})
        elif command == "threads":
            self.respond(request, {"threads": [{"id": 1, "name": "main"}]})
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
        elif command == "disconnect":
            self.respond(request)
            return False
        else:
            self.send(
                {
                    "type": "response",
                    "request_seq": request["seq"],
                    "command": command,
                    "success": False,
                    "message": f"fake adapter does not support {command}",
                    "body": {},
                }
            )
        return True

    def run(self) -> int:
        self.trace("start", mode=self.mode)
        while (request := read_message(self.input)) is not None:
            if not self.handle(request):
                exit_code = 17 if self.mode == "exit-before-initialize-response" else 0
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
