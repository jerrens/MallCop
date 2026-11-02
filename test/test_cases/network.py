# Checks that need the real network. Skipped with --offline.

test_cases = {
    "-f {{LIST}} network": {
        "name": "network_group",
        "see": r"^  https://www\.google\.com\s+200 ✓$.*^  example\.com certificate expires:\s+✓.*^  DNS www\.example\.com\s+✓\s+(\d+)/\1$",
        "rc": 0,
        "timeout": 30,
    },
    "-d www.example.com": {
        "name": "dns_one_off",
        "see": r"^Host\s+DNS Resolution$.*^DNS www\.example\.com\s+✓\s+(\d+)/\1$",
        "rc": 0,
        "timeout": 20,
    },
}
