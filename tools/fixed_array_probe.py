#!/usr/bin/env python3
"""Probe raw MoonBit FixedArray values without loading LLDB formatters."""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path
import sys
from typing import Any

from dap_capability_probe import (
    DapClient,
    ProbeError,
    discover_adapter,
    event_body,
    marker_line,
    response_body,
    same_path,
    source_path,
)


def dap_variables(client: DapClient, reference: int) -> list[dict[str, Any]]:
    variables = response_body(
        client.request("variables", {"variablesReference": reference})
    ).get("variables", [])
    return [variable for variable in variables if isinstance(variable, dict)]


def named_variable(
    variables: list[dict[str, Any]], name: str
) -> dict[str, Any]:
    for variable in variables:
        if variable.get("name") == name:
            return variable
    available = [variable.get("name") for variable in variables]
    raise ProbeError(
        f"variable {name!r} was not found; available variables: {available}"
    )


def selected_source_frame(
    client: DapClient, thread_id: int, source: Path
) -> dict[str, Any]:
    frames = response_body(
        client.request(
            "stackTrace",
            {"threadId": thread_id, "startFrame": 0, "levels": 20},
        )
    ).get("stackFrames", [])
    for frame in frames:
        if isinstance(frame, dict) and same_path(source_path(frame), source):
            return frame
    raise ProbeError("stopped stack has no frame for the MoonBit source")


def local_variables(
    client: DapClient, frame_id: int
) -> list[dict[str, Any]]:
    scopes = response_body(
        client.request("scopes", {"frameId": frame_id})
    ).get("scopes", [])
    for scope in scopes:
        if not isinstance(scope, dict) or scope.get("name") != "Locals":
            continue
        reference = scope.get("variablesReference")
        if isinstance(reference, int) and reference > 0:
            return dap_variables(client, reference)
    raise ProbeError("stopped frame has no Locals scope")


def read_array_header(
    client: DapClient, memory_reference: str
) -> tuple[bytes, int]:
    response = response_body(
        client.request(
            "readMemory",
            {"memoryReference": memory_reference, "offset": -8, "count": 8},
        )
    )
    encoded = response.get("data")
    unreadable = response.get("unreadableBytes", 0)
    if not isinstance(encoded, str) or unreadable not in (0, None):
        raise ProbeError(f"array header could not be read completely: {response}")
    header = base64.b64decode(encoded, validate=True)
    if len(header) != 8:
        raise ProbeError(f"array header has {len(header)} bytes instead of 8")
    return header, int.from_bytes(header[4:8], "little", signed=False)


def evaluate_element(
    client: DapClient,
    frame_id: int,
    body_evaluate_name: str,
    index: int,
) -> dict[str, Any]:
    return response_body(
        client.request(
            "evaluate",
            {
                "expression": f"{body_evaluate_name}[{index}]",
                "frameId": frame_id,
                "context": "watch",
            },
        )
    )


def variable_summary(variable: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": variable.get("name"),
        "type": variable.get("type"),
        "value": variable.get("value"),
        "evaluateName": variable.get("evaluateName"),
        "memoryReference": variable.get("memoryReference"),
        "variablesReference": variable.get("variablesReference"),
    }


def inspect_stop(
    client: DapClient, stopped: dict[str, Any], source: Path
) -> dict[str, Any]:
    thread_id = event_body(stopped).get("threadId")
    if not isinstance(thread_id, int):
        raise ProbeError("FixedArray stop has no integer thread id")
    frame = selected_source_frame(client, thread_id, source)
    frame_id = frame.get("id")
    if not isinstance(frame_id, int):
        raise ProbeError("selected frame has no integer id")
    array = named_variable(local_variables(client, frame_id), "arr")
    reference = array.get("variablesReference")
    if not isinstance(reference, int) or reference <= 0:
        raise ProbeError("arr has no expandable raw representation")
    body = named_variable(dap_variables(client, reference), "body")
    memory_reference = body.get("memoryReference")
    evaluate_name = body.get("evaluateName")
    if not isinstance(memory_reference, str) or not isinstance(
        evaluate_name, str
    ):
        raise ProbeError("arr.body has no memoryReference or evaluateName")
    header, length = read_array_header(client, memory_reference)
    if length <= 0:
        raise ProbeError(f"fixture array has invalid length {length}")
    first = evaluate_element(client, frame_id, evaluate_name, 0)
    last = evaluate_element(client, frame_id, evaluate_name, length - 1)
    return {
        "frame": frame,
        "array": variable_summary(array),
        "body": variable_summary(body),
        "headerHex": header.hex(),
        "length": length,
        "first": first,
        "last": last,
        "threadId": thread_id,
    }


def run_probe(args: argparse.Namespace) -> tuple[dict[str, Any], bool]:
    fixture = Path(args.fixture).resolve(strict=True)
    executable = (
        fixture
        / "_build/native/debug/build/fixed_array_int/fixed_array_int.exe"
    ).resolve(strict=True)
    source = (fixture / "fixed_array_int/main.mbt").resolve(strict=True)
    line = marker_line(source, "let mut total = 0")
    client = DapClient(discover_adapter(args.adapter), args.timeout)
    report: dict[str, Any] = {
        "adapter": client.adapter,
        "executable": str(executable),
        "source": str(source),
        "breakpointLine": line,
    }
    try:
        initialize = response_body(
            client.request(
                "initialize",
                {
                    "clientID": "moondbg-fixed-array-probe",
                    "clientName": "moondbg FixedArray probe",
                    "adapterID": "lldb",
                    "pathFormat": "path",
                    "linesStartAt1": True,
                    "columnsStartAt1": True,
                    "supportsVariableType": True,
                    "supportsRunInTerminalRequest": False,
                },
            )
        )
        report["supportsReadMemoryRequest"] = initialize.get(
            "supportsReadMemoryRequest"
        )
        launch_seq = client.send_request(
            "launch", {"program": str(executable), "stopOnEntry": False}
        )
        client.wait_event("initialized")
        breakpoints = response_body(
            client.request(
                "setBreakpoints",
                {
                    "source": {"name": source.name, "path": str(source)},
                    "breakpoints": [{"line": line}],
                    "sourceModified": False,
                },
            )
        ).get("breakpoints", [])
        report["breakpoints"] = breakpoints
        client.request("configurationDone", {})

        observations: list[dict[str, Any]] = []
        for stop_index in range(2):
            stopped = client.wait_event("stopped")
            if stop_index == 0:
                client.require_response(launch_seq, "launch")
            observation = inspect_stop(client, stopped, source)
            observations.append(observation)
            client.request(
                "continue",
                {
                    "threadId": observation["threadId"],
                    "singleThread": False,
                },
            )
        client.wait_event("exited", "terminated")
        report["observations"] = observations

        lengths = [observation["length"] for observation in observations]
        first_values = [
            observation["first"].get("result")
            for observation in observations
        ]
        last_values = [
            observation["last"].get("result") for observation in observations
        ]
        checks = {
            "readMemorySupported": report["supportsReadMemoryRequest"] is True,
            "breakpointVerified": len(breakpoints) == 1
            and isinstance(breakpoints[0], dict)
            and breakpoints[0].get("verified") is True,
            "rawArrayTypes": all(
                observation["array"].get("type") == "moonbit.array_i32"
                and observation["body"].get("type") == "int *"
                for observation in observations
            ),
            "lengths": lengths == [10, 100],
            "firstElements": first_values == ["1", "1"],
            "lastElements": last_values == ["10", "100"],
        }
        report["checks"] = checks
        report["allChecksPassed"] = all(checks.values())
        return report, bool(report["allChecksPassed"])
    finally:
        report["messageOrder"] = client.message_order
        report["adapterStderr"] = client.shutdown()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Probe raw FixedArray values through real lldb-dap."
    )
    parser.add_argument(
        "--fixture", default="testdata/dwarf_probe", type=Path
    )
    parser.add_argument("--adapter")
    parser.add_argument("--timeout", type=float, default=15.0)
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
