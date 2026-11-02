#!/usr/bin/env python3
# spell-checker:ignore MallCop dnsutils iputils

import argparse
import glob
import http.server
import os
import re
import shlex
import shutil
import socket
import subprocess
import sys
import tempfile
import threading

TEST_ROOT = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(TEST_ROOT)
exe = os.path.join(REPO_ROOT, "mallPatrol.sh")

DEFAULT_TIMEOUT = 5
NETWORK_FILE = "network"  # test_cases file skipped by --offline

DEFAULT_CONTAINER_IMAGE = "docker.io/library/ubuntu:latest"
CONTAINER_WORKDIR = "/mnt/host"
CONTAINER_PACKAGES = "python3 curl dnsutils netcat-openbsd iputils-ping openssl"

ANSI_RE = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def parse_container_args(argv):
    """Pull --container/-c [IMAGE] out of argv so the rest can be forwarded to the container."""
    use_container = False
    image = None
    remaining = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("--container", "-c"):
            use_container = True
            if i + 1 < len(argv) and not argv[i + 1].startswith("-"):
                image = argv[i + 1]
                i += 1
        elif arg.startswith("--container=") or arg.startswith("-c="):
            use_container = True
            image = arg.split("=", 1)[1].strip() or None
        else:
            remaining.append(arg)
        i += 1
    return use_container, image, remaining


def parse_args(argv):
    parser = argparse.ArgumentParser(
        description="Test runner for mallPatrol.sh. Loads test cases from test_cases/*.py.",
        epilog="""examples:
  python3 test.py                     run all tests on the current OS
  python3 test.py --offline           skip tests that need the real network
  python3 test.py -f '^ping'          run tests whose name matches a regex
  python3 test.py --test-file cli,http
  python3 test.py -n -f http          list matching tests without running them
  python3 test.py -c                  run in the default container (%s)
  python3 test.py -c=docker.io/library/debian:stable-slim -d
""" % DEFAULT_CONTAINER_IMAGE,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("-c", "--container", metavar="IMAGE", nargs="?",
                        help="run the tests inside a container (default image: %s)" % DEFAULT_CONTAINER_IMAGE)
    parser.add_argument("-f", "--filter", metavar="REGEX",
                        help="run only tests whose name (or key when no name is set) matches REGEX")
    parser.add_argument("--test-file", metavar="FILE1,FILE2",
                        help="load only these test_cases files (comma-separated, .py optional)")
    parser.add_argument("--offline", action="store_true",
                        help=f"skip tests in test_cases/{NETWORK_FILE}.py")
    parser.add_argument("-n", "--dryrun", action="store_true", help="list tests without running them")
    parser.add_argument("-d", "--debug", action="store_true", help="print each command before running it")
    return parser.parse_args(argv)


def detect_container_engine():
    for engine in ("podman", "docker"):
        if shutil.which(engine):
            return engine
    return None


def run_in_container(image, forwarded_args, debug):
    engine = detect_container_engine()
    if not engine:
        print("Error: Neither 'podman' nor 'docker' is installed.")
        return 1

    image = image or DEFAULT_CONTAINER_IMAGE
    inner_args = " ".join(shlex.quote(a) for a in forwarded_args)
    inner_command = (
        "echo 'Installing test dependencies...'; "
        "apt-get update -qq >/dev/null; "
        # ca-certificates postinst can fail on first configure under podman; a retry completes it
        f"apt-get install -y -qq {CONTAINER_PACKAGES} >/dev/null 2>&1 || dpkg --configure -a >/dev/null 2>&1; "
        "for t in python3 curl dig nc ping openssl; do command -v $t >/dev/null "
        "|| { echo \"Error: Failed to install test dependency: $t\" >&2; exit 127; }; done; "
        f"cd {CONTAINER_WORKDIR}/test && python3 test.py {inner_args}"
    )
    cmd = [
        engine, "run", "-i", "--rm",
        "--cap-add=NET_RAW",  # needed by ping
        "-e", "DEBIAN_FRONTEND=noninteractive",
        "-e", "LC_ALL=C.UTF-8",  # bash printf only renders \u2713 in a UTF-8 locale
        "--volume", f"{REPO_ROOT}:{CONTAINER_WORKDIR}",
        "--workdir", CONTAINER_WORKDIR,
        image, "bash", "-c", inner_command,
    ]

    print(f"Container mode enabled ({engine}) using image: {image}")
    if debug:
        print(">> Executing in container: " + " ".join(shlex.quote(p) for p in cmd))
    return subprocess.run(cmd).returncode


def load_all_test_cases(test_cases_dir, only_files=None, skip_files=()):
    """Return (test_cases, source_files) merged from every test_cases/*.py file."""
    all_cases = {}
    source_files = {}
    for file in sorted(glob.glob(os.path.join(test_cases_dir, "*.py"))):
        base_name = os.path.splitext(os.path.basename(file))[0]
        if only_files is not None and base_name not in only_files:
            continue
        if base_name in skip_files:
            continue

        local_ns = {}
        with open(file, "r") as f:
            exec(f.read(), {}, local_ns)
        cases = local_ns.get("test_cases")
        if not isinstance(cases, dict):
            print(f"Warning: {file} does not define a test_cases dictionary.")
            continue
        for key in cases:
            source_files[key] = base_name
        all_cases.update(cases)
    return all_cases, source_files


def test_name(key, val):
    return val.get("name", key) if isinstance(val, dict) else key


def substitute(text, subs):
    for placeholder, value in subs.items():
        text = text.replace(placeholder, value)
    return text


class StatusHandler(http.server.BaseHTTPRequestHandler):
    """Replies with the status code given in the path, e.g. GET /404 -> 404."""

    def do_GET(self):
        code = self.path.strip("/")
        self.send_response(int(code) if code.isdigit() else 200)
        self.end_headers()

    def log_message(self, *args):
        pass


def start_local_services():
    """Start the HTTP server and an open TCP port, and pick a closed port. Returns (subs, cleanup)."""
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), StatusHandler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()

    open_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    open_sock.bind(("127.0.0.1", 0))
    open_sock.listen()

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        closed_port = s.getsockname()[1]

    subs = {
        "{{HTTP_PORT}}": str(httpd.server_address[1]),
        "{{OPEN_PORT}}": str(open_sock.getsockname()[1]),
        "{{CLOSED_PORT}}": str(closed_port),
    }

    def cleanup():
        httpd.shutdown()
        httpd.server_close()
        open_sock.close()

    return subs, cleanup


def run_tests(test_cases, test_dir, subs, debug):
    """Run every test and return (passed, failed)."""
    passed = failed = 0
    for key, val in test_cases.items():
        if not isinstance(val, dict):
            val = {"see": val}

        # Section headers
        if key.startswith("#"):
            print(f"\n{val.get('see', '')}\n" + "-" * 30)
            continue

        name = test_name(key, val)
        description = val.get("description", "")
        expected = substitute(val.get("see", ""), subs)
        expected_rc = val.get("rc")
        raw = val.get("raw", False)
        timeout = val.get("timeout", DEFAULT_TIMEOUT)
        pwd = val.get("pwd", test_dir)
        cwd = pwd if os.path.isabs(pwd) else os.path.join(test_dir, pwd)

        if "raw_cmd" in val:
            test_cmd = val["raw_cmd"]
        else:
            test_cmd = f"{val.get('pre', '')} {shlex.quote(exe)} {val.get('cmd', key)}".strip()
        test_cmd = substitute(test_cmd.replace("__exe__", shlex.quote(exe)), subs)

        if debug:
            print(f">> Executing: {test_cmd}")

        try:
            result = subprocess.run(
                test_cmd,
                capture_output=True,
                text=True,
                timeout=timeout,
                shell=True,
                executable=shutil.which("bash"),
                env=val.get("env"),
                cwd=cwd,
            )
        except subprocess.TimeoutExpired:
            print(f"\033[1;31m✗ {name:<50} {description}\n    Timed out after {timeout}s\n    Command   {test_cmd}\033[0m")
            failed += 1
            continue
        except Exception as e:
            print(f"\033[1;31m✗ {name:<50} Error: {e}\033[0m")
            failed += 1
            continue

        stdout = result.stdout or ""
        stderr = result.stderr or ""
        if not raw:
            stdout = ANSI_RE.sub("", stdout)
            stderr = ANSI_RE.sub("", stderr)
        # Trim only newlines so leading indentation can be matched
        actual = (stdout + ("\n" if stdout and stderr else "") + stderr).strip("\n")
        alternate = (stderr + ("\n" if stderr and stdout else "") + stdout).strip("\n")

        pattern = re.compile(expected, re.DOTALL | re.MULTILINE)
        output_ok = bool(pattern.search(actual) or pattern.search(alternate))
        rc_ok = expected_rc is None or result.returncode == expected_rc

        if output_ok and rc_ok:
            print(f"✓ {name:<50} {description}")
            passed += 1
        else:
            print("\033[1;31m", end="")
            print(f"✗ {name:<50} {description}")
            if not output_ok:
                print(f"    Expected: {expected!r}")
                print(f"    Got:      {actual!r}")
            if not rc_ok:
                print(f"    Exit code: {result.returncode} (expected {expected_rc})")
            print(f"    Command   {test_cmd}")
            print("\033[0m", end="")
            failed += 1
    return passed, failed


def print_dryrun(test_cases, source_files):
    rows = [(test_name(k, v), source_files.get(k, "unknown"), k,
             v.get("description", "") if isinstance(v, dict) else "")
            for k, v in test_cases.items() if not k.startswith("#")]
    name_w = max((len(r[0]) for r in rows), default=4)
    src_w = max((len(r[1]) for r in rows), default=5)
    print("\n=== Tests that would be run ===\n")
    print(f"{'Name':<{name_w}}    {'File':<{src_w}}    Arguments / Description")
    print("-" * (name_w + src_w + 50))
    for name, src, key, desc in rows:
        detail = f"{key}  {desc}" if name != key else desc
        print(f"{name:<{name_w}}    {src:<{src_w}}    {detail.strip()}")
    print(f"\nTotal: {len(rows)} tests")


def main():
    use_container, image, forwarded = parse_container_args(sys.argv[1:])
    args = parse_args(forwarded)

    if use_container:
        return run_in_container(image, forwarded, args.debug)

    only_files = None
    if args.test_file:
        only_files = [f.strip().removesuffix(".py") for f in args.test_file.split(",")]
        print(f"Loading only test cases from: {', '.join(only_files)}")
    skip_files = (NETWORK_FILE,) if args.offline else ()
    if args.offline:
        print(f"Offline mode: skipping test_cases/{NETWORK_FILE}.py")

    test_cases, source_files = load_all_test_cases(
        os.path.join(TEST_ROOT, "test_cases"), only_files, skip_files)

    if args.filter:
        try:
            pattern = re.compile(args.filter)
        except re.error as e:
            print(f"Error: Invalid regex pattern '{args.filter}': {e}")
            return 1
        test_cases = {k: v for k, v in test_cases.items()
                      if not k.startswith("#") and pattern.search(test_name(k, v))}
        print(f"Filtering tests by regex: {args.filter}")

    if args.dryrun:
        print_dryrun(test_cases, source_files)
        return 0

    test_dir = tempfile.mkdtemp(prefix="mallcop_test_")
    subs, stop_services = start_local_services()
    list_path = os.path.join(test_dir, "test.list")
    subs.update({"{{TEST_DIR}}": test_dir, "{{LIST}}": list_path})

    with open(os.path.join(TEST_ROOT, "test.list"), "r") as src, open(list_path, "w") as dst:
        dst.write(substitute(src.read(), subs))

    print(f"Test directory: {test_dir}")
    print("Starting tests...\n")

    passed = failed = 0
    try:
        passed, failed = run_tests(test_cases, test_dir, subs, args.debug)
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user (Ctrl+C)")
        failed = max(failed, 1)
    finally:
        stop_services()
        shutil.rmtree(test_dir, ignore_errors=True)

        print(f"\n{'=' * 40}")
        print(f"Test Summary: {passed}/{passed + failed} passed")
        if failed:
            print(f"Failed: {failed}")
        print("=" * 40)

    return failed


if __name__ == "__main__":
    sys.exit(main())
