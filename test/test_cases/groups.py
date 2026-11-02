# Group selection with -g, positional group names, and the option value forms

test_cases = {
    "-f {{LIST}} -g ping": {
        "name": "group_single",
        "see": r"\A(?!.*http:).*^ping:$\n  127\.0\.0\.1\s+✓$",
        "rc": 0,
    },
    "-f {{LIST}} -g=ping": {"name": "group_equals_form", "see": r"^ping:$\n  127\.0\.0\.1\s+✓$", "rc": 0},
    "--file {{LIST}} --group port": {"name": "group_long_form", "see": r"^port:$", "rc": 0},
    "-f {{LIST}} -g ping -g port": {
        "name": "group_repeated",
        "see": r"^ping:$.*^port:$",
        "rc": 0,
    },
    "{{LIST}} ping port": {
        "name": "group_positional_with_file",
        "see": r"\A(?!.*http:).*^ping:$.*^port:$",
        "rc": 0,
    },
    "-f {{LIST}} nosuch": {
        "name": "group_unknown",
        "see": r"\ATarget\s+Response\n-+\s*\Z",
        "rc": 0,
        "description": "Unknown group prints only the header",
    },
    "-f {{LIST}} -g ping -g ping_fail": {
        "name": "group_error_count",
        "see": r"^Errors:\n   Host unreachable: nonexistent\.invalid",
        "rc": 1,
        "description": "Exit code equals the number of errors",
    },
}
