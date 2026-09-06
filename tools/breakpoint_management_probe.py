#!/usr/bin/env python3
"""T-07/P1 raw adapter diagnostic; not a product/runtime Python dependency.

Build with `printf 'quit\n' | moon debug breakpoint_management` in the fixture,
then run this file from the repository root. Full protocol evidence is printed
as JSON (or saved with --output), independently of moondbg's implementation.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any

from dap_capability_probe import (
    DapClient, ProbeError, discover_adapter, event_body, marker_line, response_body, same_path,
)


BASE = "_M0FP316Kaida_2dAmethyst23moondbg_2ddwarf_2dprobe22breakpoint__management"
ORDINARY = BASE + "8ordinary"
FAMILY = "^" + BASE + "8identity($|G|H)"


class RecordingClient(DapClient):
    def __init__(self, adapter: str, timeout: float):
        self.transcript: list[dict[str, Any]] = []
        super().__init__(adapter, timeout)

    def send_request(self, command: str, arguments: dict[str, Any]) -> int:
        self.transcript.append({"direction": "request", "seq": self.next_seq,
                                "command": command, "arguments": arguments})
        return super().send_request(command, arguments)

    def receive(self) -> dict[str, Any]:
        message = super().receive()
        self.transcript.append({"direction": "received", "message": message})
        return message


def probe(args: argparse.Namespace) -> dict[str, Any]:
    fixture = Path(args.fixture).resolve(strict=True)
    source = fixture / "breakpoint_management/main.mbt"
    executable = fixture / "_build/native/debug/build/breakpoint_management/breakpoint_management.exe"
    executable.resolve(strict=True)
    ordinary_line = marker_line(source, "MOONDBG_BREAKPOINT_ORDINARY")
    checkpoint_line = marker_line(source, "MOONDBG_BREAKPOINT_CHECKPOINT")
    client = RecordingClient(discover_adapter(args.adapter), args.timeout)
    checks: dict[str, bool] = {}
    observations: dict[str, Any] = {}
    report: dict[str, Any] = {"adapter": client.adapter, "checks": checks,
                              "observations": observations, "transcript": client.transcript}

    def check(name: str, value: bool):
        checks[name] = value
        if not value:
            raise ProbeError("check failed: " + name)

    def command(text: str) -> str:
        body = response_body(client.request("evaluate", {"expression": text, "context": "repl"}))
        result = body.get("result")
        if not isinstance(result, str):
            raise ProbeError("evaluate has no string result")
        return result

    def sources(lines: list[int]) -> list[dict[str, Any]]:
        return response_body(client.request("setBreakpoints", {
            "source": {"path": str(source)}, "sourceModified": False,
            "breakpoints": [{"line": line} for line in lines],
        }))["breakpoints"]

    def exact(names: list[str]) -> list[dict[str, Any]]:
        return response_body(client.request("setFunctionBreakpoints", {
            "breakpoints": [{"name": name} for name in names],
        }))["breakpoints"]

    def create_family(regex: str) -> tuple[int, str]:
        result = command("breakpoint set --func-regex " + json.dumps(regex))
        match = re.search(r"Breakpoint (\d+):", result)
        if match is None:
            raise ProbeError("family creation has no cleanup handle: " + result)
        return int(match[1]), result

    def brief(handle: int) -> str:
        return command(f"breakpoint list --brief {handle}")

    def exists(handle: int) -> bool:
        return re.search(rf"^{handle}:", brief(handle), re.MULTILINE) is not None

    def resume(thread_id: int) -> dict[str, Any]:
        client.request("continue", {"threadId": thread_id})
        event = client.wait_event("stopped", "exited", "terminated")
        if event.get("event") != "stopped":
            raise ProbeError("unexpected program exit: " + str(event))
        stop = event_body(event)
        frames = response_body(client.request("stackTrace", {
            "threadId": stop["threadId"], "startFrame": 0, "levels": 1,
        }))["stackFrames"]
        return {"stopped": stop, "frame": frames[0]}

    try:
        initialize = client.request("initialize", {
            "clientID": "moondbg-breakpoint-management-probe", "clientName": "moondbg probe",
            "adapterID": "lldb-dap", "pathFormat": "path", "linesStartAt1": True,
            "columnsStartAt1": True, "supportsRunInTerminalRequest": False,
        })
        report["version"] = response_body(initialize).get("$__lldb_version")
        launch_seq = client.send_request("launch", {
            "program": str(executable), "stopOnEntry": False,
            "preRunCommands": ["!settings set target.input-path /dev/null"],
        })
        client.wait_event("initialized")
        entry = exact(["moonbit_main"])[0]
        client.request("configurationDone", {})
        first_stop = event_body(client.wait_event("stopped"))
        client.require_response(launch_seq, "launch")
        thread_id = first_stop["threadId"]
        check("entryVerified", entry.get("verified") is True)

        source_pair = sources([ordinary_line, checkpoint_line])
        exact_pair = exact(["moonbit_main", ORDINARY])
        family_id, family_create = create_family(FAMILY)
        missing_id, missing_create = create_family("^_M0FP_missing_for_t07($|G|H)")
        observations["initialMixed"] = {"source": source_pair, "exact": exact_pair,
            "family": {"lldbId": family_id, "result": family_create},
            "missing": {"lldbId": missing_id, "result": missing_create}}
        check("familyTwoLocations", "2 locations" in family_create)
        check("zeroLocationHasHandle", "no locations" in missing_create and exists(missing_id))
        check("zeroLocationDeleteConfirmed", command(f"breakpoint delete {missing_id}").strip() == "1 breakpoints deleted; 0 breakpoint locations disabled.")
        check("zeroLocationRemoved", not exists(missing_id))

        # DAP currently returns the same LLDB integer, but each protocol owns its
        # identifiers. This is evidence, not permission to conflate their types.
        check("dapIdsCurrentlyAddressLldbRecords", all(exists(item["id"]) for item in source_pair + exact_pair))
        check("sourceHasStructuredLocation", all(same_path(item.get("source", {}).get("path"), source)
            and isinstance(item.get("line"), int) for item in source_pair))
        check("exactHasStructuredLocation", all(same_path(item.get("source", {}).get("path"), source)
            and isinstance(item.get("line"), int) for item in exact_pair))

        source_duplicate = sources([ordinary_line, ordinary_line, checkpoint_line])
        exact_duplicate = exact(["moonbit_main", ORDINARY, ORDINARY])
        observations["duplicates"] = {"source": source_duplicate, "exact": exact_duplicate}
        check("duplicateTargetsShareSourceId", source_duplicate[0]["id"] == source_duplicate[1]["id"])
        check("duplicateTargetsShareExactId", exact_duplicate[1]["id"] == exact_duplicate[2]["id"])
        source_one = sources([ordinary_line, checkpoint_line])
        exact_one = exact(["moonbit_main", ORDINARY])
        check("duplicateRemovalPreservesTarget", all(item.get("verified") for item in source_one + exact_one))

        check("sourceEmptyAcknowledged", sources([]) == [])
        check("sourceEmptyRemovesOnlySource", all(not exists(item["id"]) for item in source_one)
              and all(exists(item["id"]) for item in exact_one) and exists(family_id))
        check("exactEmptyAcknowledged", exact([]) == [])
        check("exactEmptyRemovesOnlyExact", all(not exists(item["id"]) for item in exact_one) and exists(family_id))
        source_readded = sources([checkpoint_line])
        exact_readded = exact([ORDINARY])
        observations["readded"] = {"source": source_readded, "exact": exact_readded}
        check("removedIdsNotReusedInThisExecution", source_readded[0]["id"] != source_pair[1]["id"]
              and exact_readded[0]["id"] != exact_pair[1]["id"])

        summary = brief(family_id)
        details = command(f"breakpoint list --full {family_id}")
        location_query = command(f"breakpoint list {family_id}.1")
        observations["locationQuery"] = {"brief": summary, "full": details, "idDotOne": location_query}
        # LLDB's full text has only main.mbt, not a canonical source path. A
        # single-instruction DAP lookup can supply a structured location for
        # the already bounded set of addresses (no debuggee execution).
        detail_addresses = re.findall(r"address = (0x[0-9a-fA-F]+)", details)
        representative_instructions = [response_body(client.request("disassemble", {
            "memoryReference": address, "instructionCount": 1, "resolveSymbols": False,
        })).get("instructions", []) for address in detail_addresses[:8]]
        observations["locationQuery"]["singleInstructionLookups"] = representative_instructions
        check("boundedStructuredFamilySourceLookup", len(representative_instructions) == 2
              and all(len(instructions) == 1
                      and same_path(instructions[0].get("location", {}).get("path"), source)
                      and instructions[0].get("line") == marker_line(source, "MOONDBG_BREAKPOINT_GENERIC")
                      for instructions in representative_instructions))
        check("briefCountWithoutLocationExpansion", "locations = 2" in summary
              and re.search(rf"{family_id}\.\d+:", summary) is None)
        check("dotLocationIsNotPagination", f"{family_id}.1:" in location_query and f"{family_id}.2:" in location_query)
        check("familyDisableConfirmed", command(f"breakpoint disable {family_id}").strip() == "1 breakpoints disabled.")
        disabled = command(f"breakpoint list --full {family_id}")
        observations["familyDisabled"] = disabled
        check("allFamilyLocationsDisabled", "Options: disabled" in disabled
              and disabled.count("unresolved, hit count") == 2)

        ordinary_stop = resume(thread_id)
        checkpoint_stop = resume(thread_id)
        observations["disabledRun"] = [ordinary_stop, checkpoint_stop]
        check("exactStillHitsWithFamilyDisabled", exact_readded[0]["id"] in ordinary_stop["stopped"].get("hitBreakpointIds", []))
        check("bothGenericCallsSkippedWhileDisabled", checkpoint_stop["frame"]["line"] == checkpoint_line
              and source_readded[0]["id"] in checkpoint_stop["stopped"].get("hitBreakpointIds", []))
        check("familyEnableConfirmed", command(f"breakpoint enable {family_id}").strip() == "1 breakpoints enabled.")
        enabled = command(f"breakpoint list --full {family_id}")
        check("familyHandleReused", exists(family_id) and "Options: disabled" not in enabled)
        sources([])
        exact([])
        int_stop = resume(thread_id)
        double_stop = resume(thread_id)
        observations["enabledRun"] = [int_stop, double_stop]
        # stackTrace.name is the DWARF source name on this toolchain, not the
        # native GiE/GdE linkage name. Correlate both actual locations by PC,
        # full source name, and parent breakpoint ID; do not infer from a name
        # substring alone that both specializations have really stopped.
        location_addresses = re.findall(r"address = (0x[0-9a-fA-F]+)", details)
        actual_addresses = [int(stop["frame"]["instructionPointerReference"], 16)
                            for stop in (int_stop, double_stop)]
        source_prefix = "$Kaida-Amethyst/moondbg-dwarf-probe/breakpoint_management.identity"
        check("allFamilyLocationsHitAfterEnable", len(location_addresses) == 2
              and actual_addresses == [int(address, 16) for address in location_addresses]
              and actual_addresses[0] != actual_addresses[1]
              and int_stop["frame"]["name"] == source_prefix + "|[Int]|"
              and double_stop["frame"]["name"] == source_prefix + "|[Double]|"
              and all(family_id in stop["stopped"].get("hitBreakpointIds", [])
                      for stop in (int_stop, double_stop)))
        observations["familyHitIds"] = [int_stop["stopped"].get("hitBreakpointIds"), double_stop["stopped"].get("hitBreakpointIds")]
        check("familyDeleteConfirmed", "1 breakpoints deleted" in command(f"breakpoint delete {family_id}"))
        check("familyRemoved", not exists(family_id))
        invalid = command(f"breakpoint disable {family_id}")
        observations["invalidHandleSuccessfulDapResponse"] = invalid
        check("commandErrorsNeedResultInspection", "error:" in invalid)
        client.request("continue", {"threadId": thread_id})
        exit_event = client.wait_event("exited", "terminated", "stopped")
        check("deletedFamilyDoesNotStopThirdCalls", exit_event.get("event") in ("exited", "terminated"))
        report["allChecksPassed"] = all(checks.values())
    except (ProbeError, OSError, KeyError, IndexError) as error:
        report["error"] = str(error)
        report["allChecksPassed"] = False
    finally:
        report["adapterStderr"] = client.shutdown()
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", default="testdata/dwarf_probe")
    parser.add_argument("--adapter")
    parser.add_argument("--timeout", type=float, default=15.0)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = probe(args)
    rendered = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.write_text(rendered)
        print(json.dumps({"allChecksPassed": report["allChecksPassed"],
                          "checks": report["checks"], "error": report.get("error"),
                          "output": str(args.output)}, indent=2))
    else:
        print(rendered, end="")
    return 0 if report["allChecksPassed"] else 1


if __name__ == "__main__":
    sys.exit(main())
