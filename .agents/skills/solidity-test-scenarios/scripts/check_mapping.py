#!/usr/bin/env python3
"""Check named Markdown test references and reciprocal scenario IDs; optionally refresh anchors."""

import argparse
import re
from pathlib import Path


REFERENCE = re.compile(
    r"^\[(test_[A-Za-z0-9_]+)\]:[ \t]+(\S+\.t\.sol)#L([0-9]+)[ \t]*$",
    re.MULTILINE,
)
FUNCTION = re.compile(r"^[ \t]*function[ \t]+(test_[A-Za-z0-9_]+)[ \t]*\(", re.MULTILINE)
USE = re.compile(r"\[[^\]\n]*\]\[(test_[A-Za-z0-9_]+)\]")
ROW = re.compile(r"^\|[ \t]*([A-Z][A-Z0-9]*-[A-Z0-9-]+)[ \t]*\|")


def functions(path):
    source = path.read_text()
    # Ignore example declarations inside Solidity comments while preserving source positions.
    declarations = re.sub(
        r"/\*.*?\*/|//[^\n]*",
        lambda match: "".join("\n" if char == "\n" else " " for char in match[0]),
        source,
        flags=re.DOTALL,
    )
    lines = source.splitlines()
    result = {}
    for match in FUNCTION.finditer(declarations):
        line = source.count("\n", 0, match.start()) + 1
        comments = []
        index = line - 2
        while index >= 0 and (not lines[index].strip() or lines[index].lstrip().startswith("//")):
            comments.append(lines[index])
            index -= 1
        ids = set()
        for comment in comments:
            tag = re.search(r"Scenarios:[ \t]*(.*)", comment)
            if tag:
                # IDs may be followed by a sentence explaining the seeded domain.
                ids.update(re.findall(r"\b[A-Z][A-Z0-9]*-[A-Z0-9-]+\b", tag[1].split(".", 1)[0]))
        result.setdefault(match[1], []).append((line, ids))
    return result


def check(document, update=False):
    text = document.read_text()
    errors = []
    definitions = {}
    replacements = []
    cached = {}
    for match in REFERENCE.finditer(text):
        name, relative_path, old_line = match.groups()
        if name in definitions:
            errors.append(f"duplicate reference: {name}")
            continue
        definitions[name] = set()
        path = (document.parent / relative_path).resolve()
        try:
            if path not in cached:
                cached[path] = functions(path)
            candidates = cached[path].get(name, [])
        except OSError as error:
            errors.append(f"{relative_path}: {error.strerror}")
            continue
        if len(candidates) != 1:
            errors.append(f"{name}: expected one function in {relative_path}, found {len(candidates)}")
            continue
        line, ids = candidates[0]
        definitions[name] = ids
        if line != int(old_line):
            if update:
                replacements.append((match.start(3), match.end(3), str(line)))
            else:
                errors.append(f"{name}: stale L{old_line}; actual L{line}")

    used = set(USE.findall(text))
    for name in sorted(used - definitions.keys()):
        errors.append(f"undefined test reference: {name}")
    for name in sorted(definitions.keys() - used):
        errors.append(f"unused test reference: {name}")
    row_ids = set()
    row_tests = {}
    for line in text.splitlines():
        row = ROW.match(line)
        if not row:
            continue
        scenario = row[1]
        if scenario in row_ids:
            errors.append(f"duplicate scenario ID: {scenario}")
        row_ids.add(scenario)
        mapped = USE.findall(line)
        row_tests[scenario] = set(mapped)
        if "Covered:" in line and not mapped:
            errors.append(f"{scenario}: Covered row has no named test mapping")
        for name in mapped:
            if name in definitions and scenario not in definitions[name]:
                errors.append(f"{scenario}: missing reciprocal Scenarios comment on {name}")
    for name, ids in definitions.items():
        for scenario in sorted(ids - row_ids):
            errors.append(f"{name}: unknown scenario ID in Scenarios comment: {scenario}")
        for scenario in sorted(ids & row_ids):
            if name not in row_tests[scenario]:
                errors.append(f"{scenario}: missing reciprocal test reference for {name}")
    if not definitions:
        errors.append("no named test references; legacy inline links require manual validation")

    # Never partially rewrite a document if a missing/renamed test or invalid mapping remains.
    if errors:
        return errors, 0
    for start, end, value in reversed(replacements):
        text = text[:start] + value + text[end:]
    if replacements:
        document.write_text(text)
    return [], len(replacements)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("document", type=Path)
    parser.add_argument("--update", action="store_true", help="refresh line anchors after all checks pass")
    args = parser.parse_args()
    try:
        errors, changed = check(args.document, args.update)
    except OSError as error:
        parser.exit(1, f"{args.document}: {error.strerror}\n")
    if errors:
        parser.exit(1, "\n".join(errors) + "\n")
    print(f"Mapping valid; {changed} anchor(s) refreshed. Semantic coverage requires code review.")


if __name__ == "__main__":
    main()
