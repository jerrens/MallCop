# HTTP checks against the local server started by test.py (GET /<code> returns <code>)

test_cases = {
    "-f {{LIST}} http": {
        "name": "http_expected_codes",
        "see": r"^  # Local HTTP server$\n  http://127\.0\.0\.1:{{HTTP_PORT}}/200\s+200 ✓$\n  http://127\.0\.0\.1:{{HTTP_PORT}}/404\s+404 ✓$",
        "rc": 0,
    },
    "-f {{LIST}} http_fail": {
        "name": "http_unexpected_codes",
        "see": r"/500\s+500 ✗ \(Expected 200\)$.*/200\s+200 ✗ \(Expected 404\)$.*^Errors:\n   Unexpected status code: 500 \(Expected 200\)",
        "rc": 2,
    },
}
