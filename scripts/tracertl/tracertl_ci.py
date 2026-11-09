#!/usr/bin/env python3
"""TraceRTL CI: corner-case trace tests and the coremark performance check.

Each workload runs on NEMU, which records the TraceRTL trace, and then on a
TraceRTL emu fed with that trace. TraceRTL checks every committed instruction
against the trace, so a case passes when NEMU hits the good trap and the emu
commits the whole trace (exit code 0).

The NEMU is the trace collector used for the SPEC TraceRTL traces (riscv64
NEMU built with the --tracefile writer); install it at $TRACERTL_NEMU. The
tests are built with $CROSS_COMPILE and need zstd for --skip-traceinstr cases.

  tracertl_ci.py tests    --emu build/emu --work out/tests
  tracertl_ci.py coremark --emu build/emu --work out/coremark
"""

import argparse
import json
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
NOOP_HOME = SCRIPT_DIR.parents[1]
TEST_DIR = SCRIPT_DIR / "tests"
PERF_BASELINE = SCRIPT_DIR / "perf-baseline.json"

DEFAULT_NEMU = os.environ.get(
    "TRACERTL_NEMU", "/nfs/home/share/ci-workloads/tracertl/riscv64-nemu-interpreter")
DEFAULT_CROSS = os.environ.get("CROSS_COMPILE", "riscv64-unknown-linux-gnu-")
TRACE_RECORD = struct.Struct("<QQQQQIBBBB")

# Extra cases started part way into a test's trace with --skip-traceinstr, the
# way a checkpoint trace starts: <test>@skip begins at the given label.
SKIP_CASES = {
    "ctx_fp": "ctx_body",
}

# Cases known to fail, with the reason. They still run, and an unexpected pass
# fails the job so that the entry gets removed.
XFAIL = {
    "intr": "TraceRTL rejects NEMU interrupt records (pc 0, instr 0) as illegal",
    "intr_next": "TraceRTL rejects NEMU interrupt records (pc 0, instr 0) as illegal",
}


def run(cmd, log, timeout, cwd=None, env=None):
    with open(log, "w") as f:
        try:
            return subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, cwd=cwd, env=env,
                                  timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            f.write(f"\n[tracertl_ci] timed out after {timeout}s\n")
            return -1


def nemu_trace(nemu, image, prefix, timeout):
    """Record the trace of image into <prefix>.trace.zstd; returns the trace path."""
    log = Path(f"{prefix}.nemu.log")
    rc = run([nemu, "-b", f"--tracefile={prefix}", str(image)], log, timeout)
    text = log.read_text(errors="replace")
    if rc != 0 or "HIT GOOD TRAP" not in text:
        raise RuntimeError(f"NEMU did not hit the good trap on {image} (rc={rc}, see {log})")
    trace = Path(f"{prefix}.trace.zstd")
    if not trace.exists():
        raise RuntimeError(f"NEMU wrote no trace for {image} (see {log})")
    return trace


def trace_pcs(trace):
    raw = subprocess.run(["zstd", "-dc", str(trace)], check=True, capture_output=True).stdout
    return [TRACE_RECORD.unpack_from(raw, i)[0] for i in range(0, len(raw), TRACE_RECORD.size)]


def symbol_addr(elf, cross, name):
    out = subprocess.run([f"{cross}nm", str(elf)], check=True, capture_output=True, text=True).stdout
    for line in out.splitlines():
        addr, _, sym = line.split()
        if sym == name:
            return int(addr, 16)
    raise RuntimeError(f"{name} not found in {elf}")


def run_emu(emu, trace, workdir, name, extra, timeout):
    log = workdir / f"{name}.emu.log"
    cmd = [str(emu), "--no-diff", "--tracertl-file", str(trace),
           "--dramsim3-outdir", str(workdir), *extra]
    rc = run(cmd, log, timeout)
    text = log.read_text(errors="replace")
    ipc = re.findall(r"IPC = (\d+\.\d+)", text)
    reason = ""
    for marker in ("TraceRTL timed out", "TraceRTL commit mismatch", "TraceRTL drive mismatch",
                   "TraceRTL detected emulator conflict", "illegal inst", "Assertion failed",
                   "ABORT at pc"):
        if marker in text:
            reason = marker
            break
    return {"rc": rc, "ipc": float(ipc[-1]) if ipc else None, "reason": reason, "log": str(log)}


def cmd_tests(args):
    work = Path(args.work).resolve()
    build = work / "build"
    shutil.rmtree(work, ignore_errors=True)
    build.mkdir(parents=True)
    subprocess.run(["make", "-C", str(TEST_DIR), f"BUILD={build}", f"CROSS_COMPILE={args.cross}"],
                   check=True)

    names = sorted(p.stem for p in build.glob("*.bin"))
    if args.only:
        names = [n for n in names if n in args.only]
    cases = []
    for name in names:
        trace = nemu_trace(args.nemu, build / f"{name}.bin", str(work / name), args.timeout)
        cases.append((name, trace, []))
        if name in SKIP_CASES:
            start = symbol_addr(build / f"{name}.elf", args.cross, SKIP_CASES[name])
            skip = trace_pcs(trace).index(start)
            cases.append((f"{name}@skip", trace, ["--skip-traceinstr", str(skip)]))

    results, failed = [], False
    for name, trace, extra in cases:
        r = run_emu(args.emu, trace, work, name, extra, args.timeout)
        passed = r["rc"] == 0
        xfail = XFAIL.get(name.split("@")[0])
        if xfail:
            status = "XPASS" if passed else "XFAIL"
            failed |= passed
        else:
            status = "PASS" if passed else "FAIL"
            failed |= not passed
        results.append({"name": name, "status": status, **r, "note": xfail or ""})
        print(f"{status:5} {name:16} ipc={r['ipc']} {r['reason']}", flush=True)
        if status in ("FAIL", "XPASS"):
            print(f"      log: {r['log']}")

    (work / "results.json").write_text(json.dumps(results, indent=2))
    if args.summary:
        with open(args.summary, "a") as f:
            f.write("## TraceRTL corner-case tests\n\n| Test | Result | IPC | Note |\n| --- | --- | --- | --- |\n")
            for r in results:
                note = "; ".join(x for x in (r["reason"], r["note"]) if x)
                f.write(f"| {r['name']} | {r['status']} | {r['ipc'] or '-'} | {note} |\n")
            f.write("\n")
    return 1 if failed else 0


def cmd_coremark(args):
    work = Path(args.work).resolve()
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    image = Path(args.image)
    trace = nemu_trace(args.nemu, image, str(work / image.stem), args.timeout)
    r = run_emu(args.emu, trace, work, image.stem, [], args.timeout)
    if r["rc"] != 0 or r["ipc"] is None:
        print(f"FAIL  {image.stem}: TraceRTL run failed ({r['reason']}), log: {r['log']}")
        return 1

    baseline = json.loads(PERF_BASELINE.read_text())[image.stem]
    ref, tol = baseline["ipc"], args.tolerance if args.tolerance is not None else baseline["tolerance"]
    delta = (r["ipc"] - ref) / ref
    status = "FAIL" if delta < -tol else "PASS"
    print(f"{status}  {image.stem}: IPC {r['ipc']:.6f}, baseline {ref:.6f} ({delta:+.3%}, tolerance {tol:.1%})")
    if delta > tol:
        print(f"      IPC is above the baseline by more than the tolerance; update {PERF_BASELINE.name}")
    if args.ipc_out:
        Path(args.ipc_out).write_text(f"{r['ipc']}\n")
    if args.summary:
        with open(args.summary, "a") as f:
            f.write("## TraceRTL performance\n\n| Workload | IPC | Baseline | Delta | Result |\n| --- | --- | --- | --- | --- |\n")
            f.write(f"| {image.stem} | {r['ipc']:.6f} | {ref:.6f} | {delta:+.3%} | {status} |\n\n")
    (work / "result.json").write_text(json.dumps({"name": image.stem, "status": status, "baseline": ref,
                                                  "delta": delta, **r}, indent=2))
    return 1 if status == "FAIL" else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    for name in ("tests", "coremark"):
        p = sub.add_parser(name)
        p.add_argument("--emu", required=True, type=Path, help="TraceRTL emu")
        p.add_argument("--work", required=True, help="output directory (recreated)")
        p.add_argument("--nemu", default=DEFAULT_NEMU, help="trace-collecting NEMU ($TRACERTL_NEMU)")
        p.add_argument("--timeout", type=int, default=1800, help="per-run timeout in seconds")
        p.add_argument("--summary", help="append a markdown report to this file ($GITHUB_STEP_SUMMARY)")
    tests = sub.choices["tests"]
    tests.add_argument("--cross", default=DEFAULT_CROSS, help="cross-compiler prefix ($CROSS_COMPILE)")
    tests.add_argument("--only", nargs="*", help="run only these tests")
    coremark = sub.choices["coremark"]
    coremark.add_argument("--image", default=str(NOOP_HOME / "ready-to-run" / "coremark-2-iteration.bin"))
    coremark.add_argument("--tolerance", type=float, help="allowed relative IPC drop (default: baseline file)")
    coremark.add_argument("--ipc-out", help="write the IPC to this file")
    args = parser.parse_args()
    return cmd_tests(args) if args.cmd == "tests" else cmd_coremark(args)


if __name__ == "__main__":
    sys.exit(main())
