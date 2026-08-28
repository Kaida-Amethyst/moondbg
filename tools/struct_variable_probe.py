#!/usr/bin/env python3
"""Probe MoonBit struct expansion through a real lldb-dap session."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import Any

from dap_capability_probe import (
    DapClient,
    ProbeError,
    discover_adapter,
    event_body,
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
    available = [
        {
            "name": variable.get("name"),
            "type": variable.get("type"),
            "value": variable.get("value"),
        }
        for variable in variables
    ]
    raise ProbeError(
        f"variable {name!r} was not found; available variables: {available}"
    )


def child_variables(
    client: DapClient, variable: dict[str, Any]
) -> list[dict[str, Any]]:
    reference = variable.get("variablesReference")
    if not isinstance(reference, int) or reference <= 0:
        raise ProbeError(
            f"variable {variable.get('name')!r} is not expandable"
        )
    return dap_variables(client, reference)


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
    client: DapClient, thread_id: int, source: Path
) -> list[dict[str, Any]]:
    frame = selected_source_frame(client, thread_id, source)
    frame_id = frame.get("id")
    if not isinstance(frame_id, int):
        raise ProbeError("selected frame has no integer id")
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


def field_summary(variable: dict[str, Any]) -> dict[str, Any]:
    return {
        "name": variable.get("name"),
        "type": variable.get("type"),
        "value": variable.get("value"),
        "variablesReference": variable.get("variablesReference"),
    }


def run_probe(args: argparse.Namespace) -> tuple[dict[str, Any], bool]:
    fixture = Path(args.fixture).resolve(strict=True)
    executable = (
        fixture / "_build/native/debug/build/point/point.exe"
    ).resolve(strict=True)
    source = (fixture / "point/main.mbt").resolve(strict=True)
    client = DapClient(discover_adapter(args.adapter), args.timeout)
    report: dict[str, Any] = {
        "adapter": client.adapter,
        "executable": str(executable),
        "source": str(source),
    }
    try:
        client.request(
            "initialize",
            {
                "clientID": "moondbg-struct-probe",
                "clientName": "moondbg struct probe",
                "adapterID": "lldb",
                "pathFormat": "path",
                "linesStartAt1": True,
                "columnsStartAt1": True,
                "supportsVariableType": True,
                "supportsRunInTerminalRequest": False,
            },
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
                    "breakpoints": [{"line": 14}, {"line": 20}],
                    "sourceModified": False,
                },
            )
        ).get("breakpoints", [])
        report["breakpoints"] = breakpoints
        client.request("configurationDone", {})

        point_stop = client.wait_event("stopped")
        client.require_response(launch_seq, "launch")
        point_thread = event_body(point_stop).get("threadId")
        if not isinstance(point_thread, int):
            raise ProbeError("Point stop has no integer thread id")
        point = named_variable(
            local_variables(client, point_thread, source), "p1"
        )
        point_fields = child_variables(client, point)
        report["point"] = {
            "root": field_summary(point),
            "fields": [field_summary(field) for field in point_fields],
        }

        client.request(
            "continue", {"threadId": point_thread, "singleThread": False}
        )
        line_stop = client.wait_event("stopped")
        line_thread = event_body(line_stop).get("threadId")
        if not isinstance(line_thread, int):
            raise ProbeError("Line stop has no integer thread id")
        line = named_variable(
            local_variables(client, line_thread, source), "line1"
        )
        line_fields = child_variables(client, line)
        nested_fields: dict[str, list[dict[str, Any]]] = {}
        for field_name in ("start", "end"):
            field = named_variable(line_fields, field_name)
            nested_fields[field_name] = [
                field_summary(child)
                for child in child_variables(client, field)
            ]
        report["line"] = {
            "root": field_summary(line),
            "fields": [field_summary(field) for field in line_fields],
            "nestedFields": nested_fields,
        }

        client.request(
            "continue", {"threadId": line_thread, "singleThread": False}
        )
        client.wait_event("exited", "terminated")

        point_values = {
            field.get("name"): str(field.get("value"))
            for field in point_fields
        }
        point_types = {
            field.get("name"): field.get("type") for field in point_fields
        }
        line_names = [field.get("name") for field in line_fields]
        line_types = {
            field.get("name"): str(field.get("type"))
            for field in line_fields
        }
        nested_values = {
            name: {
                field.get("name"): str(field.get("value"))
                for field in fields
            }
            for name, fields in nested_fields.items()
        }
        checks = {
            "breakpointsVerified": len(breakpoints) == 2
            and all(
                isinstance(breakpoint, dict)
                and breakpoint.get("verified") is True
                for breakpoint in breakpoints
            ),
            "pointExpandable": point.get("variablesReference", 0) > 0,
            "pointType": str(point.get("type")).endswith("/Point &"),
            "pointFields": point_values == {"x": "1", "y": "2"},
            "pointFieldTypes": point_types == {"x": "double", "y": "double"},
            "lineExpandable": line.get("variablesReference", 0) > 0,
            "lineType": str(line.get("type")).endswith("/Line &"),
            "lineFields": line_names == ["start", "end"],
            "lineFieldTypes": all(
                type_name.endswith("/Point &")
                for type_name in line_types.values()
            ),
            "lineStartFields": nested_values.get("start")
            == {"x": "1", "y": "2"},
            "lineEndFields": nested_values.get("end")
            == {"x": "4", "y": "6"},
        }
        report["checks"] = checks
        report["allChecksPassed"] = all(checks.values())
        return report, bool(report["allChecksPassed"])
    finally:
        report["messageOrder"] = client.message_order
        report["adapterStderr"] = client.shutdown()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Probe MoonBit struct fields through real lldb-dap."
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
