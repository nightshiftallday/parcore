---
name: run-hw-tests
description: Run the ParCore hardware unit tests using Python unittest discovery against the Vivado simulation build.
---

## Usage

```
/run-hw-tests [filter]
```

- **No args**: run all `*_test.py` files in `hardware/unit-tests/`
- **filter**: passed as `-k` to match specific test names or classes (e.g. `page_header_parser`, `PageHeaderParserTestCase.test_single_plain_page`)

## Command

```bash
set -a && source .env && set +a && timeout 2m python3 -m unittest discover -v -s ./hardware/unit-tests -p "*_test.py" ${ARGUMENTS:+-k "$ARGUMENTS"}
```

Note: The build directory `hardware/build-sim` must exist (created by `./scripts/setup_simulation.sh`). The `-v` flag shows each test name and pass/fail as it runs.
