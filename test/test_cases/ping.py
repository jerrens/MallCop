# Ping checks against localhost and an unresolvable host

test_cases = {
    "-f {{LIST}} ping": {"name": "ping_localhost", "see": r"^  127\.0\.0\.1\s+✓$", "rc": 0},
    "-f {{LIST}} ping_fail": {
        "name": "ping_unreachable",
        "see": r"^  nonexistent\.invalid\s+✗$.*^   Host unreachable: nonexistent\.invalid$",
        "rc": 1,
    },
}
