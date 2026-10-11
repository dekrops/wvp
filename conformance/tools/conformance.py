#!/usr/bin/env python3
"""Checks of the conformance corpus that need no implementation of the protocol, and a runner
that asks public implementations to reproduce it.

    conformance.py structure   [--root DIR]
    conformance.py provenance  [--root DIR]
    conformance.py unchanged   --old DIR [--new DIR]
    conformance.py inventory   [--root DIR]
    conformance.py run         --implementation NAME --source DIR --out FILE [--root DIR]
    conformance.py report      --results DIR [--root DIR] [--out FILE]

Standard library only. What each command establishes, and what it does not, is in
conformance/ci.md. The map of the corpus it reads is conformance/corpus.json.
"""

import argparse
import fnmatch
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys

MAP = "conformance/corpus.json"
# Paths written in this repository by pull request. The export never writes them, and
# PROVENANCE.md does not list them (governance/publication.md).
WRITTEN_HERE = ("rfcs/", "governance/", "conformance/", ".github/", "CONTRIBUTING.md")
CODE = re.compile(r"^[A-Z][A-Z0-9_]*$")


class Problems:
    def __init__(self):
        self.found = []

    def add(self, where, what):
        self.found.append(f"{where}: {what}")

    def finish(self, ok):
        if self.found:
            for line in self.found:
                print(f"FAIL  {line}")
            print(f"\n{len(self.found)} problem(s).")
            sys.exit(1)
        print(ok)


# --- Reading JSON without losing what a comparison needs -------------------------------------


class Number(str):
    """A number as it was spelled: 1, 1.0 and 1e0 are different texts."""

    def __repr__(self):
        return f"number {str.__repr__(self)}"


def read_json(text):
    """Parses JSON keeping member order and number spellings, refusing duplicate members."""

    def members(pairs):
        names = [name for name, _ in pairs]
        repeated = sorted({name for name in names if names.count(name) > 1})
        if repeated:
            raise ValueError(f"duplicate member {repeated[0]!r}")
        return dict(pairs)

    return json.loads(text, object_pairs_hook=members, parse_int=Number, parse_float=Number)


def difference(old, new, at="$"):
    """The path of the first place where two parsed values differ, or None. Member order counts."""
    if type(old) is not type(new):
        return f"{at}: {kind(old)} became {kind(new)}"
    if isinstance(old, dict):
        if list(old) != list(new):
            for name in old:
                if name not in new:
                    return f"{at}: member {name!r} was removed"
            for name in new:
                if name not in old:
                    return f"{at}: member {name!r} was added"
            return f"{at}: members were reordered"
        for name in old:
            found = difference(old[name], new[name], f"{at}.{name}")
            if found:
                return found
        return None
    if isinstance(old, list):
        if len(old) != len(new):
            return f"{at}: {len(old)} elements became {len(new)}"
        for index, (a, b) in enumerate(zip(old, new)):
            found = difference(a, b, f"{at}[{index}]")
            if found:
                return found
        return None
    return None if old == new else f"{at}: {old!r} became {new!r}"


def kind(value):
    if isinstance(value, dict):
        return "an object"
    if isinstance(value, list):
        return "an array"
    return {Number: "a number", str: "a string", bool: "a boolean", type(None): "null"}[type(value)]


# --- The map ----------------------------------------------------------------------------------


def load_map(root):
    return json.loads((root / MAP).read_text(encoding="utf-8"))


def corpus_files(root):
    base = root / "test-vectors"
    return sorted(p.relative_to(root).as_posix() for p in base.rglob("*") if p.is_file())


def files_of(part, files):
    return [f for f in files if fnmatch.fnmatchcase(f, part["files"]) and f.count("/") == part["files"].count("/")]


def selected(part, value):
    return all(isinstance(value, dict) and value.get(k) == v for k, v in part.get("where", {}).items())


def entries(part, path, value):
    """The cases of one part in one parsed file, as (identity, list name, case)."""
    if part["layout"] == "one-per-file":
        if selected(part, value):
            yield path, "", value
        return
    for name, rule in part["lists"].items():
        cases = value if name == "" else value.get(name) if isinstance(value, dict) else None
        if not isinstance(cases, list):
            raise ValueError(f"no array {name or 'at the top level'!r}")
        for index, case in enumerate(cases):
            identity = index if rule["identity"] == "index" else (case.get(rule["identity"]) if isinstance(case, dict) else None)
            yield f"{path}#{name}[{identity}]", name, case


def parse(root, path, problems):
    try:
        return read_json((root / path).read_bytes().decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as error:
        problems.add(path, f"not well-formed JSON without duplicate members ({error})")
        return None


def inventory(root, problems=None):
    """How many cases each part holds, counted from the files."""
    problems = problems or Problems()
    corpus = load_map(root)
    files = corpus_files(root)
    counts = {}
    for part in corpus["parts"]:
        total = 0
        for path in files_of(part, files):
            value = parse(root, path, problems)
            if value is not None:
                try:
                    total += sum(1 for _ in entries(part, path, value))
                except ValueError as error:
                    problems.add(path, str(error))
        counts[part["id"]] = total
    return corpus, counts


# --- structure --------------------------------------------------------------------------------


def structure(args):
    root = pathlib.Path(args.root)
    problems = Problems()
    corpus, counts = inventory(root, problems)
    files = corpus_files(root)
    claimed = set(corpus["support"])
    for part in corpus["parts"]:
        claimed.update(files_of(part, files))
        if counts[part["id"]] == 0:
            problems.add(part["id"], f"no case found at {part['files']}")
    for path in files:
        if path not in claimed:
            problems.add(path, f"not named by any part of {MAP}; a new part of the corpus is added to the map in the same change")
    for path in corpus["support"]:
        if not (root / path).is_file():
            problems.add(path, f"named as support in {MAP} and missing")

    seen_files = {}
    for part in corpus["parts"]:
        for path in files_of(part, files):
            value = parse(root, path, Problems())
            if value is None:
                continue
            if part["layout"] == "one-per-file":
                seen_files.setdefault(path, []).append(selected(part, value))
                if selected(part, value):
                    check_file_case(part, path, value, problems)
            else:
                check_lists(part, path, value, problems)
    for path, hits in seen_files.items():
        if not any(hits):
            problems.add(path, "matches no part: its selecting member has a value the map does not know")
    problems.finish(f"structure: {sum(counts.values())} cases in {len(corpus['parts'])} parts, {len(files)} files, all well-formed.")


def check_file_case(part, path, value, problems):
    stem = pathlib.PurePosixPath(path).stem
    folder = pathlib.PurePosixPath(path).parent.name
    expected = value.get("expected")
    if not isinstance(expected, dict) or not expected:
        problems.add(path, "no expectation: `expected` must be a non-empty object")
        return
    if part.get("named", True) and value.get("name") != stem:
        problems.add(path, f"`name` is {value.get('name')!r} and the file is {stem!r}")
    if "protocol" in part and value.get("protocol") != part["protocol"]:
        problems.add(path, f"`protocol` is {value.get('protocol')!r}, expected {part['protocol']!r}")
    if not part.get("accept_member", True):
        return
    accept = expected.get("accept")
    if not isinstance(accept, bool):
        problems.add(path, "`expected.accept` must be true or false")
    elif accept != (folder == "valid"):
        problems.add(path, f"`expected.accept` is {str(accept).lower()} in directory {folder!r}")
    elif not accept and not (isinstance(expected.get("error"), str) and CODE.match(expected["error"])):
        problems.add(path, "a refused case must state its refusal code in `expected.error`")


def check_lists(part, path, value, problems):
    identities = {}
    try:
        cases = list(entries(part, path, value))
    except ValueError:
        return
    for identity, name, case in cases:
        rule = part["lists"][name]
        if not isinstance(case, dict):
            problems.add(identity, "a case must be an object")
            continue
        if rule["identity"] != "index":
            key = case.get(rule["identity"])
            if not isinstance(key, str) or not key:
                problems.add(identity, f"no `{rule['identity']}` to identify the case by")
            elif identities.setdefault((name, key), identity) is not identity:
                problems.add(identity, f"`{rule['identity']}` {key!r} is used twice")
        for member in rule["expectation"]:
            if case.get(member) in (None, "", {}, []):
                problems.add(identity, f"no expectation: `{member}` is absent or empty")
        if part.get("self_check") == "canonical-digest" and "sha256" in rule["expectation"]:
            digest = hashlib.sha256(str(case.get("canonicalUtf8", "")).encode("utf-8")).hexdigest()
            if digest != case.get("sha256"):
                problems.add(identity, f"`sha256` is not the SHA-256 of `canonicalUtf8` ({digest})")


# --- provenance -------------------------------------------------------------------------------


def provenance(args):
    """Every exported file is the file PROVENANCE.md says the export wrote."""
    root = pathlib.Path(args.root)
    problems = Problems()
    listed = dict(re.findall(r"^\| `([^`]+)` \| `([0-9a-f]{64})` \|", (root / "PROVENANCE.md").read_text(encoding="utf-8"), re.M))
    if not listed:
        problems.add("PROVENANCE.md", "lists no file")
    tracked = subprocess.run(["git", "ls-files", "-z"], cwd=root, check=True, capture_output=True).stdout.decode().split("\0")
    exported = [p for p in tracked if p and p != "PROVENANCE.md" and not p.startswith(WRITTEN_HERE)]
    for path in exported:
        if path not in listed:
            problems.add(path, "is not listed in PROVENANCE.md, and is not on a path written in this repository")
    for path, digest in listed.items():
        file = root / path
        if not file.is_file():
            problems.add(path, "is listed in PROVENANCE.md and missing")
        elif hashlib.sha256(file.read_bytes()).hexdigest() != digest:
            problems.add(path, "differs from the export recorded in PROVENANCE.md. Specifications, vectors and examples change by export (governance/publication.md)")
    problems.finish(f"provenance: {len(listed)} exported files match PROVENANCE.md.")


# --- unchanged --------------------------------------------------------------------------------


def unchanged(args):
    """No published expectation changed between two trees (RFC 0001, invariant 1).

    Judged by the old tree's map: a part that was published keeps every case it had. A file with
    one case is unchanged byte for byte. A file of cases may gain cases, and nothing else in it
    may change. Prose (Markdown) is not an expectation and is not compared.
    """
    old, new = pathlib.Path(args.old), pathlib.Path(args.new)
    problems = Problems()
    if not (old / "test-vectors").is_dir():
        print("unchanged: the earlier tree has no corpus; nothing to compare.")
        return
    parts = load_map(old)["parts"] if (old / MAP).is_file() else []
    files = corpus_files(old)
    kept = cases = compared = 0
    for path in files:
        if path.endswith(".md"):
            continue
        compared += 1
        if not (new / path).is_file():
            problems.add(path, "a published file was removed")
            continue
        before, after = (old / path).read_bytes(), (new / path).read_bytes()
        growing = [p for p in parts if p["layout"] == "lists" and path in files_of(p, files)]
        if before == after:
            kept += 1
            continue
        if not growing:
            problems.add(path, "a published file was changed. A change of outcome is a new version, in a new directory")
            continue
        try:
            was, now = read_json(before.decode("utf-8")), read_json(after.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as error:
            problems.add(path, f"cannot be read ({error})")
            continue
        for part in growing:
            lists = part["lists"]
            if isinstance(was, dict):
                rest = lambda value: {k: v for k, v in value.items() if k not in lists} if isinstance(value, dict) else value
                found = difference(rest(was), rest(now))
                if found:
                    problems.add(path, f"changed outside its cases, at {found}")
            later = {identity: case for identity, _, case in entries(part, path, now)}
            for identity, _, case in entries(part, path, was):
                cases += 1
                if identity not in later:
                    problems.add(identity, "a published case was removed, renamed or moved")
                    continue
                found = difference(case, later[identity])
                if found:
                    problems.add(identity, f"a published case was changed, at {found}")
    problems.finish(f"unchanged: {compared} published files compared; {kept} identical, and every one of {cases} cases in the files that grew is as it was.")


# --- run --------------------------------------------------------------------------------------


def run(args):
    """Asks one implementation to reproduce the parts the map says it is run against."""
    root = pathlib.Path(args.root).resolve()
    corpus, counts = inventory(root)
    vectors = root / "test-vectors"
    environment = dict(os.environ, VERIFIED_CONFORMANCE_DIR=str(vectors), VERIFIED_CONFORMANCE_REQUIRED="1")
    outputs, results = {}, []
    for check in corpus["checks"]:
        if check["implementation"] != args.implementation:
            continue
        argv = [word.replace("{corpus}", str(vectors)) for word in check["argv"]]
        key = tuple(argv)
        if key not in outputs:
            print(f"$ {' '.join(argv)}", flush=True)
            done = subprocess.run(argv, cwd=args.source, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
            print(done.stdout, flush=True)
            outputs[key] = done
        done = outputs[key]
        total = sum(counts[part] for part in check["covers"])
        reproduced = count(check.get("reproduced"), done.stdout)
        unrepresentable = count(check.get("unrepresentable"), done.stdout) or 0
        if done.returncode != 0:
            status, detail = "failed", tail(done.stdout)
        elif reproduced is None:
            status, detail = "failed", "The run passed without saying how many cases it ran, so nothing can be concluded from it. The implementation's output no longer matches `reproduced` in the map."
        elif reproduced + unrepresentable != total:
            status, detail = "failed", f"The run passed, having run {reproduced + unrepresentable} cases where this revision of the corpus holds {total}. Cases it did not run are not reproduced."
        else:
            status, detail = ("partial" if unrepresentable else "reproduced"), ""
        results.append({"implementation": args.implementation, "covers": check["covers"], "status": status, "total": total, "reproduced": reproduced, "unrepresentable": unrepresentable, "caveat": check.get("caveat", ""), "detail": detail, "command": " ".join(check["argv"])})
        print(f"{status.upper():10} {', '.join(check['covers'])}: {reproduced} of {total}", flush=True)
    pathlib.Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    pathlib.Path(args.out).write_text(json.dumps({"implementation": args.implementation, "results": results}, indent=2) + "\n", encoding="utf-8")
    if not results:
        sys.exit(f"the map names no check for implementation {args.implementation!r}")


def count(pattern, output):
    if not pattern:
        return None
    match = re.search(pattern, output)
    return sum(int(group) for group in match.groups()) if match else None


def tail(output, lines=60):
    """The end of a failing run: where an implementation names the case and the two outcomes."""
    return "\n".join(output.strip().splitlines()[-lines:])


# --- report -----------------------------------------------------------------------------------


def report(args):
    root = pathlib.Path(args.root)
    corpus, counts = inventory(root)
    names = list(corpus["implementations"])
    results, ran = {}, set()
    for file in sorted(pathlib.Path(args.results).rglob("*.json")):
        data = json.loads(file.read_text(encoding="utf-8"))
        ran.add(data["implementation"])
        for result in data["results"]:
            for part in result["covers"]:
                results[(result["implementation"], part)] = result
    expected = {(c["implementation"], part) for c in corpus["checks"] for part in c["covers"]}

    def label(name):
        implementation = corpus["implementations"][name]
        return implementation["name"] + (f" `{implementation['tag']}`" if "tag" in implementation else "")

    notes, failures = [], []

    def cell(name, part):
        result = results.get((name, part))
        if (name, part) not in expected:
            return "not implemented"
        if result is None:
            failures.append(f"**{label(name)}, {part}:** did not run.")
            return "**did not run**"
        across = f" across {len(result['covers'])} parts" if len(result["covers"]) > 1 else ""
        text = {"reproduced": f"reproduced ({result['reproduced']}{across})", "partial": f"partial: {result['reproduced']} of {result['total']}{across}; {result['unrepresentable']} cannot be represented", "failed": "**FAILED**"}[result["status"]]
        if result["status"] == "failed":
            failure = f"**{label(name)}, {', '.join(result['covers'])}:**\n\n`{result['command']}`\n\n```text\n{result['detail']}\n```"
            if failure not in failures:
                failures.append(failure)
        if result["caveat"]:
            if result["caveat"] not in notes:
                notes.append(result["caveat"])
            text += f", except [{notes.index(result['caveat']) + 1}]"
        return text

    def standing(name, part):
        """Whole only if every case was run and the whole expectation of each was compared."""
        result = results.get((name, part), {})
        if result.get("status") == "reproduced" and not result.get("caveat"):
            return "whole"
        return "partial" if result.get("status") in ("reproduced", "partial") else None

    lines = ["## Conformance of public implementations", ""]
    lines += ["Each number is counted from the files of this revision, and each result is what the implementation reported when run against them. `not implemented` means no public implementation is run against that part: it is a gap in coverage, and not a failed test.", ""]
    lines += ["| Specification | Part | Cases | " + " | ".join(label(n) for n in names) + " | Public implementations that reproduce it |", "| --- | --- | ---: | " + " | ".join("---" for _ in names) + " | ---: |"]
    total = once = twice = 0
    for part in corpus["parts"]:
        cells = [cell(name, part["id"]) for name in names]
        whole = sum(1 for name in names if standing(name, part["id"]) == "whole")
        some = sum(1 for name in names if standing(name, part["id"]))
        total += counts[part["id"]]
        once += counts[part["id"]] if some else 0
        twice += counts[part["id"]] if some > 1 else 0
        lines.append(f"| `{part['specification']}` | {part['title']} | {counts[part['id']]} | " + " | ".join(cells) + f" | {whole if whole == some else f'{whole} whole, {some - whole} partial'} |")
    lines += ["", f"**{total} cases.** {once} are in parts that at least one public implementation reproduces, wholly or partially; {twice} in parts that two do; {total - once} in parts that none is run against."]
    lines += [""] + [f"{index}. {note}" for index, note in enumerate(notes, 1)]
    lines += ["", "Implementations run:", ""]
    for name in names:
        implementation = corpus["implementations"][name]
        where = implementation["repository"] + (f" at `{implementation['commit']}`" if "commit" in implementation else "")
        lines.append(f"- **{label(name)}** ({implementation['language']}), {where}. {implementation['independent']}" + ("" if name in ran else " **It did not run.**"))
    if failures:
        lines += ["", "### Failures", "", "An expectation is never edited to make an implementation pass (RFC 0001, invariant 1). A failure is either a defect of the implementation at its pinned revision, or a change here that it does not reproduce.", ""]
        for failure in failures:
            lines += [failure, ""]
    text = "\n".join(lines) + "\n"
    if args.out:
        pathlib.Path(args.out).write_text(text, encoding="utf-8")
    print(text)
    if failures:
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    for name, function in (("structure", structure), ("provenance", provenance), ("unchanged", unchanged), ("inventory", None), ("run", run), ("report", report)):
        command = commands.add_parser(name)
        command.add_argument("--root", default=".", help="a checkout of this repository")
        command.set_defaults(function=function)
        if name == "unchanged":
            command.add_argument("--old", required=True, help="a checkout of the earlier revision")
            command.add_argument("--new", default=".", help="a checkout of the later revision")
        if name == "run":
            command.add_argument("--implementation", required=True)
            command.add_argument("--source", required=True, help="the directory to run the implementation's commands in")
            command.add_argument("--out", required=True)
        if name == "report":
            command.add_argument("--results", required=True, help="a directory of files written by `run`")
            command.add_argument("--out")
    args = parser.parse_args()
    if args.command == "inventory":
        corpus, counts = inventory(pathlib.Path(args.root))
        for part in corpus["parts"]:
            print(f"{counts[part['id']]:5}  {part['specification']:32} {part['title']}")
        print(f"{sum(counts.values()):5}  total")
        return
    args.function(args)


if __name__ == "__main__":
    main()
