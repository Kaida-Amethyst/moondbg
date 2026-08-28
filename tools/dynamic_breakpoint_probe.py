#!/usr/bin/env python3
"""Probe stopped-state breakpoint updates against a real lldb-dap.

This development diagnostic fixes the protocol assumptions used by Q-02. It
deliberately talks to lldb-dap directly so a bug in moondbg cannot make the
probe pass accidentally.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any

from dap_capability_probe import (
    DapClient,
    ProbeError,
    discover_adapter,
    event_body,
    response_body,
)


DEFAULT_SUM_NAME = (
    "_M0FP316Kaida_2dAmethyst23moondbg_2ddwarf_2dprobe4main3sum"
)
DEFAULT_IDENTITY_BASE = (
    "_M0FP316Kaida_2dAmethyst23moondbg_2ddwarf_2dprobe3lib8identity"
)
DEFAULT_MISSING_BASE = (
    "_M0FP316Kaida_2dAmethyst23moondbg_2ddwarf_2dprobe4main7missing"
)


def breakpoint_list(response: dict[str, Any]) -> list[dict[str, Any]]:
    breakpoints = response_body(response).get("breakpoints", [])
    return [item for item in breakpoints if isinstance(item, dict)]


def breakpoint_id(breakpoint: dict[str, Any]) -> int | None:
    value = breakpoint.get("id")
    return value if isinstance(value, int) else None


def collect_breakpoint_events(
    client: DapClient, timeout: float = 0.2
) -> list[dict[str, Any]]:
    events: list[dict[str, Any]] = []
    while True:
        event = client.try_wait_event(timeout, "breakpoint")
        if event is None:
            return events
        events.append(event_body(event))


def family_result(response: dict[str, Any]) -> str:
    result = response_body(response).get("result", "")
    return result if isinstance(result, str) else ""


def family_summary(response: dict[str, Any]) -> dict[str, Any]:
    result = family_result(response)
    match = re.search(r"Breakpoint (\d+): (\d+) locations?\.", result)
    if match is not None:
        adapter_id, location_count = match.groups()
        return {
            "adapterId": int(adapter_id),
            "locationCount": int(location_count),
            "result": result,
        }
    pending = re.search(r"Breakpoint (\d+): no locations \(pending\)\.", result)
    return {
        "adapterId": int(pending.group(1)) if pending is not None else None,
        "locationCount": 0 if pending is not None else None,
        "result": result,
    }


def evaluate_family(client: DapClient, regex: str) -> dict[str, Any]:
    expression = f"breakpoint set --func-regex {json.dumps(regex)}"
    return client.request(
        "evaluate", {"expression": expression, "context": "repl"}
    )


def run_probe(args: argparse.Namespace) -> tuple[dict[str, Any], bool]:
    fixture = Path(args.fixture).resolve(strict=True)
    executable = (
        fixture / "_build/native/debug/build/main/main.exe"
    ).resolve(strict=True)
    main_source = (fixture / "main/main.mbt").resolve(strict=True)
    adapter = discover_adapter(args.adapter)
    family_regex = f"^{args.identity_base}($|G|H)"
    missing_regex = f"^{args.missing_base}($|G|H)"
    report: dict[str, Any] = {
        "adapter": adapter,
        "executable": str(executable),
        "observations": {},
    }
    observations = report["observations"]
    assert isinstance(observations, dict)
    client = DapClient(adapter, args.timeout)
    try:
        client.request(
            "initialize",
            {
                "clientID": "moondbg-q02-probe",
                "clientName": "moondbg Q-02 probe",
                "adapterID": "lldb-dap",
                "pathFormat": "path",
                "linesStartAt1": True,
                "columnsStartAt1": True,
                "supportsRunInTerminalRequest": False,
            },
        )
        launch_seq = client.send_request(
            "launch", {"program": str(executable), "stopOnEntry": False}
        )
        client.wait_event("initialized")
        initial_exact = breakpoint_list(
            client.request(
                "setFunctionBreakpoints",
                {"breakpoints": [{"name": "moonbit_main"}]},
            )
        )
        client.request("configurationDone", {})
        initial_stop = client.wait_event("stopped")
        client.require_response(launch_seq, "launch")
        initial_events = collect_breakpoint_events(client, 0.3)
        observations["initial"] = {
            "breakpoints": initial_exact,
            "stopped": event_body(initial_stop),
            "breakpointEvents": initial_events,
        }

        first_source = breakpoint_list(
            client.request(
                "setBreakpoints",
                {
                    "source": {
                        "name": main_source.name,
                        "path": str(main_source),
                    },
                    "breakpoints": [{"line": 13}],
                    "sourceModified": False,
                },
            )
        )
        first_source_events = collect_breakpoint_events(client)
        complete_source = breakpoint_list(
            client.request(
                "setBreakpoints",
                {
                    "source": {
                        "name": main_source.name,
                        "path": str(main_source),
                    },
                    "breakpoints": [{"line": 13}, {"line": 14}],
                    "sourceModified": False,
                },
            )
        )
        complete_source_events = collect_breakpoint_events(client)
        observations["sourceReplacement"] = {
            "first": first_source,
            "firstEvents": first_source_events,
            "complete": complete_source,
            "completeEvents": complete_source_events,
        }

        complete_exact = breakpoint_list(
            client.request(
                "setFunctionBreakpoints",
                {
                    "breakpoints": [
                        {"name": "moonbit_main"},
                        {"name": args.sum_name},
                    ]
                },
            )
        )
        exact_events = collect_breakpoint_events(client)
        observations["exactReplacement"] = {
            "breakpoints": complete_exact,
            "events": exact_events,
        }

        first_family = family_summary(evaluate_family(client, family_regex))
        first_family_events = collect_breakpoint_events(client)
        duplicate_family = family_summary(evaluate_family(client, family_regex))
        duplicate_family_events = collect_breakpoint_events(client)
        missing_family = family_summary(evaluate_family(client, missing_regex))
        missing_family_events = collect_breakpoint_events(client)
        observations["functionFamily"] = {
            "first": first_family,
            "firstEvents": first_family_events,
            "duplicate": duplicate_family,
            "duplicateEvents": duplicate_family_events,
            "missing": missing_family,
            "missingEvents": missing_family_events,
        }

        invalid_seq = client.send_request(
            "setBreakpoints", {"breakpoints": [{"line": 3}]}
        )
        invalid_response = client.wait_response(invalid_seq)
        observations["invalidRequest"] = {
            "success": invalid_response.get("success"),
            "message": invalid_response.get("message"),
            "body": response_body(invalid_response),
        }

        client.request(
            "setBreakpoints",
            {
                "source": {"name": main_source.name, "path": str(main_source)},
                "breakpoints": [],
                "sourceModified": False,
            },
        )
        collect_breakpoint_events(client)

        exact_sum_id = (
            breakpoint_id(complete_exact[1]) if len(complete_exact) == 2 else None
        )
        thread_id = event_body(initial_stop).get("threadId")
        if not isinstance(thread_id, int):
            raise ProbeError("initial stopped event has no integer threadId")
        client.request(
            "continue", {"threadId": thread_id, "singleThread": False}
        )
        dynamic_stop = client.wait_event("stopped")
        observations["dynamicStop"] = event_body(dynamic_stop)

        initial_id = (
            breakpoint_id(initial_exact[0]) if len(initial_exact) == 1 else None
        )
        first_source_id = (
            breakpoint_id(first_source[0]) if len(first_source) == 1 else None
        )
        checks = {
            "initialFunctionVerified": len(initial_exact) == 1
            and initial_exact[0].get("verified") is True,
            "sourceFullSetVerified": len(complete_source) == 2
            and all(item.get("verified") is True for item in complete_source),
            "sourceExistingIdRetained": first_source_id is not None
            and breakpoint_id(complete_source[0]) == first_source_id,
            "exactFullSetVerified": len(complete_exact) == 2
            and all(item.get("verified") is True for item in complete_exact),
            "exactExistingIdRetained": initial_id is not None
            and breakpoint_id(complete_exact[0]) == initial_id,
            "familyHasTwoLocations": first_family["locationCount"] == 2,
            "duplicateCreatesNewBreakpoint": first_family["adapterId"] is not None
            and duplicate_family["adapterId"] != first_family["adapterId"]
            and duplicate_family["locationCount"] == 2,
            "missingFamilyHasZeroLocations": missing_family["locationCount"] == 0,
            "familyCommandsEmitNoBreakpointEvent": not first_family_events
            and not duplicate_family_events
            and not missing_family_events,
            "invalidRequestRejected": invalid_response.get("success") is False,
            "dynamicExactBreakpointStops": exact_sum_id is not None
            and exact_sum_id in event_body(dynamic_stop).get("hitBreakpointIds", []),
        }
        report["checks"] = checks
        report["allChecksPassed"] = all(checks.values())
        return report, bool(report["allChecksPassed"])
    finally:
        report["messageOrder"] = client.message_order
        report["adapterStderr"] = client.shutdown()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Probe stopped-state breakpoint updates in lldb-dap."
    )
    parser.add_argument(
        "fixture", nargs="?", default="testdata/dwarf_probe"
    )
    parser.add_argument("--adapter")
    parser.add_argument("--sum-name", default=DEFAULT_SUM_NAME)
    parser.add_argument("--identity-base", default=DEFAULT_IDENTITY_BASE)
    parser.add_argument("--missing-base", default=DEFAULT_MISSING_BASE)
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
