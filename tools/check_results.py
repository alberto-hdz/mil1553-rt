"""Exit with an error if a cocotb results file has a failing test.
cocotb's make returns 0 even when tests fail, so CI needs this check."""
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
total = 0
failed = []
for case in root.iter("testcase"):
    total += 1
    if case.find("failure") is not None or case.find("error") is not None:
        failed.append(case.get("name"))

if total == 0:
    print("check_results: no tests ran")
    sys.exit(1)
if failed:
    print(f"check_results: {len(failed)} of {total} failed: {', '.join(failed)}")
    sys.exit(1)
print(f"check_results: {total} of {total} passed")
