#!/usr/bin/env python3
"""Record the raw stack/frame/locals shape exposed by a real lldb-dap.

This is an explicit T-06/P1 diagnostic. It deliberately stays outside the
default test suite and does not depend on moondbg's stack presentation model.
"""

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
    marker_line,
    response_body,
    same_path,
    source_path,
)


LEAF_MARKER = "MOONDBG_STACK_LEAF_BREAKPOINT"


class RecordingDapClient(DapClient):
    """DapClient with a compact, ordered protocol transcript."""

    def __init__(self, adapter: str, timeout: float) -> None:
        super().__init__(adapter, timeout)
        self.protocol_order: list[dict[str, Any]] = []

    def send_request(self, command: str, arguments: dict[str, Any]) -> int:
        seq = self.next_seq
        self.protocol_order.append(
            {
                "direction": "clientToAdapter",
                "type": "request",
                "seq": seq,
                "command": command,
                "arguments": arguments,
            }
        )
        return super().send_request(command, arguments)

    def receive(self) -> dict[str, Any]:
        message = super().receive()
        entry: dict[str, Any] = {
            "direction": "adapterToClient",
            "type": message.get("type"),
            "seq": message.get("seq"),
        }
        if message.get("type") == "response":
            entry.update(
                {
                    "command": message.get("command"),
                    "requestSeq": message.get("request_seq"),
                    "success": message.get("success"),
                }
            )
        elif message.get("type") == "event":
            entry["event"] = message.get("event")
        elif message.get("type") == "request":
            entry["command"] = message.get("command")
        self.protocol_order.append(entry)
        return message


def availability(value: object) -> str:
    if not isinstance(value, str):
        return "unknown"
    lowered = value.lower()
    unavailable_markers = (
        "<unavailable>",
        "optimized out",
        "not available",
        "could not be read",
    )
    if any(marker in lowered for marker in unavailable_markers):
        return "unavailable"
    return "available"


def raw_response(
    client: RecordingDapClient,
    command: str,
    arguments: dict[str, Any],
) -> dict[str, Any]:
    seq = client.send_request(command, arguments)
    return client.wait_response(seq)


def variable_record(variable: dict[str, Any]) -> dict[str, Any]:
    return {
        "availability": availability(variable.get("value")),
        "raw": variable,
    }


def load_stack_pages(
    client: RecordingDapClient,
    thread_id: int,
    page_size: int,
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    pages: list[dict[str, Any]] = []
    frames: list[dict[str, Any]] = []
    start_frame = 0
    for _ in range(100):
        arguments = {
            "threadId": thread_id,
            "startFrame": start_frame,
            "levels": page_size,
        }
        response = client.request("stackTrace", arguments)
        body = response_body(response)
        page_frames = [
            frame
            for frame in body.get("stackFrames", [])
            if isinstance(frame, dict)
        ]
        total_frames = body.get("totalFrames")
        pages.append(
            {
                "request": arguments,
                "totalFrames": total_frames,
                "returned": len(page_frames),
                "stackFrames": page_frames,
            }
        )
        frames.extend(page_frames)
        if len(page_frames) < page_size:
            break
        start_frame += len(page_frames)
    else:
        raise ProbeError("stackTrace pagination exceeded 100 requests")
    return pages, frames


def inspect_frame(
    client: RecordingDapClient,
    physical_index: int,
    frame: dict[str, Any],
) -> dict[str, Any]:
    frame_id = frame.get("id")
    if not isinstance(frame_id, int):
        return {
            "physicalIndex": physical_index,
            "frame": frame,
            "scopesError": "frame has no integer id",
            "scopes": [],
        }
    scopes_response = raw_response(client, "scopes", {"frameId": frame_id})
    record: dict[str, Any] = {
        "physicalIndex": physical_index,
        "frame": frame,
        "scopesResponse": {
            "success": scopes_response.get("success"),
            "message": scopes_response.get("message"),
        },
        "scopes": [],
    }
    if not scopes_response.get("success"):
        return record
    scopes = [
        scope
        for scope in response_body(scopes_response).get("scopes", [])
        if isinstance(scope, dict)
    ]
    for scope in scopes:
        scope_record: dict[str, Any] = {"raw": scope}
        reference = scope.get("variablesReference")
        if (
            scope.get("name") == "Locals"
            and isinstance(reference, int)
            and reference > 0
        ):
            variables_response = raw_response(
                client,
                "variables",
                {"variablesReference": reference},
            )
            scope_record["variablesResponse"] = {
                "success": variables_response.get("success"),
                "message": variables_response.get("message"),
            }
            scope_record["variables"] = [
                variable_record(variable)
                for variable in response_body(variables_response).get(
                    "variables", []
                )
                if isinstance(variable, dict)
            ]
        record["scopes"].append(scope_record)
    return record


def local_variables(frame_record: dict[str, Any]) -> list[dict[str, Any]]:
    variables: list[dict[str, Any]] = []
    for scope in frame_record.get("scopes", []):
        if not isinstance(scope, dict):
            continue
        raw = scope.get("raw")
        if not isinstance(raw, dict) or raw.get("name") != "Locals":
            continue
        for variable in scope.get("variables", []):
            if isinstance(variable, dict):
                variables.append(variable)
    return variables


def frame_name(frame: dict[str, Any]) -> str:
    name = frame.get("name")
    return name if isinstance(name, str) else ""


def expected_chain_checks(
    pages: list[dict[str, Any]],
    frames: list[dict[str, Any]],
    frame_records: list[dict[str, Any]],
    support_source: Path,
    main_source: Path,
    marker: int,
) -> dict[str, bool]:
    names = [frame_name(frame) for frame in frames]
    frame_ids = [frame.get("id") for frame in frames]
    return {
        "usedMultipleSmallPages": len(pages) >= 2
        and all(page["request"].get("levels") < len(frames) for page in pages),
        "finalTotalFramesMatches": bool(pages)
        and pages[-1].get("totalFrames") == len(frames),
        "physicalIndexesContiguous": [
            record.get("physicalIndex") for record in frame_records
        ]
        == list(range(len(frames))),
        "frameIdsUnique": len(frame_ids) == len(set(frame_ids)),
        "genericLeafAtPhysicalZero": bool(names)
        and names[0].startswith("_M0F")
        and names[0].endswith("13generic__leafGiE")
        and same_path(source_path(frames[0]), support_source)
        and frames[0].get("line") == marker,
        "fourRecursiveFrames": sum(
            name.endswith("16recursive__frame") for name in names
        )
        == 4,
        "ordinaryFramePresent": any(
            name.endswith("15ordinary__frame") for name in names
        ),
        "crossPackageFramePresent": any(
            name.endswith("12enter__stack") for name in names
        ),
        "moonbitMainSourcePresent": any(
            name == "moonbit_main" and same_path(source_path(frame), main_source)
            for name, frame in zip(names, frames)
        ),
        "nativeBoundaryPresent": any(name == "main" for name in names)
        and any("start" == name or name.endswith("`start") for name in names),
        "allFramesInspected": len(frame_records) == len(frames)
        and all("scopesResponse" in record for record in frame_records),
        "allScopesRequestsSucceeded": all(
            record.get("scopesResponse", {}).get("success") is True
            for record in frame_records
        ),
    }


def finding_summary(
    pages: list[dict[str, Any]], frame_records: list[dict[str, Any]]
) -> dict[str, Any]:
    moonbit_records = [
        record
        for record in frame_records
        if isinstance(record.get("frame"), dict)
        and str(source_path(record["frame"]) or "").endswith(".mbt")
    ]
    unavailable: list[dict[str, Any]] = []
    duplicates: list[dict[str, Any]] = []
    for record in moonbit_records:
        seen_names: set[str] = set()
        duplicate_names: set[str] = set()
        for variable in local_variables(record):
            raw = variable.get("raw", {})
            name = raw.get("name") if isinstance(raw, dict) else None
            evaluate_name = (
                raw.get("evaluateName") if isinstance(raw, dict) else None
            )
            identity = evaluate_name if isinstance(evaluate_name, str) else name
            if isinstance(identity, str):
                if identity in seen_names:
                    duplicate_names.add(identity)
                seen_names.add(identity)
            if variable.get("availability") == "unavailable":
                unavailable.append(
                    {
                        "physicalIndex": record.get("physicalIndex"),
                        "frame": frame_name(record["frame"]),
                        "name": name,
                        "value": (
                            raw.get("value") if isinstance(raw, dict) else None
                        ),
                    }
                )
        if duplicate_names:
            duplicates.append(
                {
                    "physicalIndex": record.get("physicalIndex"),
                    "frame": frame_name(record["frame"]),
                    "names": sorted(duplicate_names),
                }
            )
    recursive_depths: list[dict[str, Any]] = []
    for record in moonbit_records:
        frame = record["frame"]
        if not frame_name(frame).endswith("16recursive__frame"):
            continue
        depth = next(
            (
                variable
                for variable in local_variables(record)
                if isinstance(variable.get("raw"), dict)
                and variable["raw"].get("name") == "recursion_depth"
            ),
            None,
        )
        recursive_depths.append(
            {
                "physicalIndex": record.get("physicalIndex"),
                "availability": depth.get("availability") if depth else "missing",
                "value": depth.get("raw", {}).get("value") if depth else None,
            }
        )
    locals_references = [
        scope.get("raw", {}).get("variablesReference")
        for record in frame_records
        for scope in record.get("scopes", [])
        if isinstance(scope, dict)
        and isinstance(scope.get("raw"), dict)
        and scope["raw"].get("name") == "Locals"
    ]
    return {
        "reportedTotalFrames": [page.get("totalFrames") for page in pages],
        "reportedTotalFramesStable": len(
            {
                page.get("totalFrames")
                for page in pages
                if isinstance(page.get("totalFrames"), int)
            }
        )
        == 1,
        "localsScopeReferences": locals_references,
        "localsScopeReferencesUnique": len(locals_references)
        == len(set(locals_references)),
        "unavailableMoonBitVariables": unavailable,
        "duplicateLocalNames": duplicates,
        "recursiveDepths": recursive_depths,
    }


def run_probe(args: argparse.Namespace) -> tuple[dict[str, Any], bool]:
    fixture = Path(args.fixture).resolve(strict=True)
    executable = (
        fixture
        / "_build/native/debug/build/stack_frames/stack_frames.exe"
    ).resolve(strict=True)
    support_source = (fixture / "stack_support/stack_support.mbt").resolve(
        strict=True
    )
    main_source = (fixture / "stack_frames/main.mbt").resolve(strict=True)
    line = marker_line(support_source, LEAF_MARKER)
    client = RecordingDapClient(discover_adapter(args.adapter), args.timeout)
    report: dict[str, Any] = {
        "schemaVersion": 1,
        "adapter": client.adapter,
        "fixture": str(fixture),
        "executable": str(executable),
        "breakpoint": {"source": str(support_source), "line": line},
        "pageSize": args.page_size,
    }
    try:
        initialize = client.request(
            "initialize",
            {
                "clientID": "moondbg-stack-frame-probe",
                "clientName": "moondbg stack/frame probe",
                "adapterID": "lldb",
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
        breakpoints = response_body(
            client.request(
                "setBreakpoints",
                {
                    "source": {
                        "name": support_source.name,
                        "path": str(support_source),
                    },
                    "breakpoints": [{"line": line}],
                    "sourceModified": False,
                },
            )
        ).get("breakpoints", [])
        report["breakpointResponse"] = breakpoints
        client.request("configurationDone", {})
        stopped = client.wait_event("stopped")
        client.require_response(launch_seq, "launch")
        report["stoppedEvent"] = event_body(stopped)
        thread_id = event_body(stopped).get("threadId")
        if not isinstance(thread_id, int):
            raise ProbeError("stopped event has no integer threadId")
        report["threadId"] = thread_id

        pages, frames = load_stack_pages(client, thread_id, args.page_size)
        report["stackPages"] = pages
        frame_records = [
            inspect_frame(client, index, frame)
            for index, frame in enumerate(frames)
        ]
        report["frames"] = frame_records
        checks = expected_chain_checks(
            pages,
            frames,
            frame_records,
            support_source,
            main_source,
            line,
        )
        checks["breakpointVerified"] = len(breakpoints) == 1 and bool(
            isinstance(breakpoints[0], dict)
            and breakpoints[0].get("verified") is True
        )
        report["checks"] = checks
        report["findings"] = finding_summary(pages, frame_records)

        old_locals_reference: int | None = None
        if frame_records:
            top_frame_id = frame_records[0].get("frame", {}).get("id")
            if isinstance(top_frame_id, int):
                reselected_scopes = raw_response(
                    client, "scopes", {"frameId": top_frame_id}
                )
                reselected_scope_list = [
                    scope
                    for scope in response_body(reselected_scopes).get(
                        "scopes", []
                    )
                    if isinstance(scope, dict)
                ]
                old_locals_reference = next(
                    (
                        scope.get("variablesReference")
                        for scope in reselected_scope_list
                        if scope.get("name") == "Locals"
                        and isinstance(scope.get("variablesReference"), int)
                    ),
                    None,
                )
                reselection_record: dict[str, Any] = {
                    "success": reselected_scopes.get("success"),
                    "scopes": reselected_scope_list,
                }
                if (
                    isinstance(old_locals_reference, int)
                    and old_locals_reference > 0
                ):
                    reselected_variables = raw_response(
                        client,
                        "variables",
                        {"variablesReference": old_locals_reference},
                    )
                    reselection_record["variablesResponse"] = {
                        "success": reselected_variables.get("success"),
                        "message": reselected_variables.get("message"),
                    }
                    reselection_record["variableNames"] = [
                        variable.get("name")
                        for variable in response_body(reselected_variables).get(
                            "variables", []
                        )
                        if isinstance(variable, dict)
                    ]
                report["reselectedTopFrame"] = reselection_record

        continue_response = raw_response(
            client,
            "continue",
            {"threadId": thread_id, "singleThread": False},
        )
        report["continueResponse"] = {
            "success": continue_response.get("success"),
            "message": continue_response.get("message"),
            "body": response_body(continue_response),
        }
        if frame_records:
            old_frame_id = frame_records[0].get("frame", {}).get("id")
            if isinstance(old_frame_id, int):
                stale_scopes = raw_response(
                    client, "scopes", {"frameId": old_frame_id}
                )
                report["postContinueOldFrameScopes"] = {
                    "success": stale_scopes.get("success"),
                    "message": stale_scopes.get("message"),
                    "body": response_body(stale_scopes),
                }
        if isinstance(old_locals_reference, int) and old_locals_reference > 0:
            stale_variables = raw_response(
                client,
                "variables",
                {"variablesReference": old_locals_reference},
            )
            report["postContinueOldLocalsVariables"] = {
                "success": stale_variables.get("success"),
                "message": stale_variables.get("message"),
                "body": response_body(stale_variables),
            }
        exited = client.wait_event("exited", "terminated")
        report["exitEvent"] = {
            "event": exited.get("event"),
            "body": event_body(exited),
        }
        client.try_wait_event(2.0, "terminated")

        report["allChecksPassed"] = all(checks.values())
        return report, bool(report["allChecksPassed"])
    finally:
        report["adapterStderr"] = client.shutdown()
        report["protocolOrder"] = client.protocol_order


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Record paginated stackTrace, per-frame scopes and Locals from "
            "the T-06 stack_frames fixture through a real lldb-dap."
        )
    )
    parser.add_argument(
        "--fixture", default="testdata/dwarf_probe", type=Path
    )
    parser.add_argument("--adapter")
    parser.add_argument(
        "--page-size",
        type=int,
        default=3,
        help="stackTrace levels per request (default: 3)",
    )
    parser.add_argument("--timeout", type=float, default=15.0)
    args = parser.parse_args()
    if args.page_size <= 0:
        parser.error("--page-size must be positive")
    try:
        report, succeeded = run_probe(args)
    except (OSError, ValueError, ProbeError) as error:
        json.dump(
            {
                "schemaVersion": 1,
                "allChecksPassed": False,
                "fatalError": str(error),
            },
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
