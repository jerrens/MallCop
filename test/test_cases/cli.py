# Command line parsing, help, version, and argument errors
# Key = arguments passed to mallPatrol.sh. Value = regex, or a dict with: name, see, rc, raw, timeout, description, pre, cmd, raw_cmd, env, pwd
# Placeholders: {{LIST}}, {{TEST_DIR}}, {{HTTP_PORT}}, {{OPEN_PORT}}, {{CLOSED_PORT}}

test_cases = {
    "--version": {"name": "version", "see": r"^\d{2}\.\d{1,2}\.\d{1,2}$", "rc": 0},
    "-h": {"name": "help_short", "see": r"Syntax:.*Version: \d", "rc": 0},
    "--help": {"name": "help_long", "see": r"Syntax:.*List File:", "rc": 0},

    "-x": {"name": "error_invalid_option", "see": r"^Error: Invalid option -x$", "rc": 1},
    "-vx": {"name": "error_invalid_verbose", "see": r"^Error: Invalid option -vx$", "rc": 1},
    "-g": {"name": "error_missing_value", "see": r"^Error: Option -g requires an argument\.$", "rc": 1},
    "-f nosuch.list": {"name": "error_missing_file", "see": r"^Error: File 'nosuch\.list' not found\.$", "rc": 1},
    "-d example.com -g ping": {"name": "error_dns_with_group", "see": r"^Error: Option '-d' cannot be used with", "rc": 1},
    "-d example.com extra": {"name": "error_dns_positional", "see": r"^Error: Positional arguments are not supported with '-d'", "rc": 1},

    "-f {{LIST}} -l": {
        "name": "list_groups",
        "see": r"^  ping\n  ping_fail\n  http\n  http_fail\n  port\n  port_fail\n  network$",
        "rc": 0,
    },
    "--file={{LIST}} --list": {"name": "list_groups_long_equals", "see": r"^  ping$", "rc": 0},
}
