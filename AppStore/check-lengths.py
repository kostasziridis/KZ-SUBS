#!/usr/bin/env python3
"""Check every App Store field against its limit before anything is pasted in.

App Store Connect silently truncates or refuses; finding out here is cheaper.
"""
import pathlib, re, sys

LIMITS = {"App Name": 30, "Subtitle": 30, "Promotional Text": 170,
          "Keywords": 100, "Description": 4000, "What's New": 4000}

text = (pathlib.Path(__file__).parent / "metadata.md").read_text()
sections = re.split(r"^## ", text, flags=re.M)

worst = 0
for section in sections:
    language = section.splitlines()[0].strip() if section.strip() else ""
    if language not in ("English (Primary)", "Ελληνικά"):
        continue
    print(f"\n{language}")
    for field, limit in LIMITS.items():
        match = re.search(rf"^### {re.escape(field)}[^\n]*\n(.*?)(?=^### |\Z)",
                          section, flags=re.M | re.S)
        if not match:
            continue
        value = match.group(1).strip()
        used = len(value)
        over = used > limit
        worst = max(worst, used - limit)
        print(f"  {'✗' if over else '✓'} {field:<18} {used:>5} / {limit}")
        if field == "Keywords" and " " in value:
            print("      note: spaces in the keyword field are wasted characters")

sys.exit(1 if worst > 0 else 0)
