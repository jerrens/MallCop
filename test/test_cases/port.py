# Port checks against a local listening socket and a closed port

test_cases = {
    "-f {{LIST}} port": {"name": "port_open", "see": r"^  Port {{OPEN_PORT}} \(127\.0\.0\.1\)\s+✓$", "rc": 0},
    "-f {{LIST}} port_fail": {
        "name": "port_closed",
        "see": r"^  Port {{CLOSED_PORT}} \(127\.0\.0\.1\)\s+✗$.*^   Port {{CLOSED_PORT}} on 127\.0\.0\.1 is closed$",
        "rc": 1,
    },
}
