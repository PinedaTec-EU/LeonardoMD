"""Plan CI from a bounded GitHub comparison and additive PR labels."""
import html
import json
import os
import re
import subprocess
from pathlib import Path

SUITES = frozenset({"macos", "ios", "package", "plugin"})
NATIVE = SUITES - {"plugin"}
DESKTOP = NATIVE - {"ios"}
PLUGIN = "plugins/leonardo-format/"
PLUGIN_SKILL = PLUGIN + "skills/leonardo-format/"
COMPARE_FILE_LIMIT = 300


def suites_for(path):
    if path.startswith("Mobile/LittleLeonardo/Legal/"):
        return {"ios", "package"}
    if path.startswith(("Mobile/", "doc/validation/git-retirement/fixtures/")):
        return {"ios"}
    if path.startswith(("Sources/LeonardoApp/", "assets/", "doc/guide/")):
        return DESKTOP
    if path.startswith((
        "Sources/CLeonardoZlib/", "Sources/LeonardoCore/", "Sources/LeonardoRender/",
        "Sources/LeonardoSync/", "Sources/LeonardoSyncTransport/", "Sources/LeonardoSyncUI/",
        "Sources/LeonardoDesktopSync/", "Sources/LeonardoSyncHelper/",
    )):
        return NATIVE
    if path.startswith(("doc/format/", "Tests/FormatContractFixtures/")):
        return SUITES
    if path.startswith(("Tests/Packaging/", "doc/validation/sync-helper/")) or path in {
        "doc/user-guide.md", "doc/user-guide-es.md",
    }:
        return {"package"}
    if path.startswith((
        "Tests/LeonardoAppTests/", "Tests/LeonardoCoreTests/", "Tests/LeonardoDesktopSyncTests/",
        "Tests/LeonardoIntegrationTests/", "Tests/LeonardoRenderTests/",
        "Tests/LeonardoSyncTests/", "Tests/LeonardoSyncTransportTests/",
    )):
        return {"macos"}
    if path.startswith(PLUGIN_SKILL + "scripts/") or path == PLUGIN_SKILL + "references/mdlf-v1.schema.json":
        return DESKTOP | {"plugin"}
    if path.startswith(PLUGIN):
        return {"plugin"}
    if path in {"README.md", "design-qa.md", ".github/pull_request_template.md"} or (
        path.endswith(".md") and path.startswith((".wiki/", "doc/adr/", "doc/design/", "doc/mobile/", "doc/plugins/"))
    ) or (
        path.startswith("doc/validation/") and path.endswith(".md") and "/fixtures/" not in path
    ) or re.fullmatch(r"deploy/version/entries/[1-9][0-9]*\.yaml", path):
        return set()
    return SUITES


def api(path):
    result = subprocess.run(
        ["gh", "api", path], capture_output=True, text=True, check=True, timeout=60,
    )
    return json.loads(result.stdout)


def compared_paths(comparison, base, expected_count):
    files = comparison["files"]
    if (
        comparison["status"] not in {"ahead", "diverged"}
        or comparison["base_commit"]["sha"] != base
        or not isinstance(files, list)
        or type(expected_count) is not int
        or not 0 < len(files) == expected_count < COMPARE_FILE_LIMIT
    ):
        raise ValueError("the comparison is empty, incomplete, or reached the GitHub file limit")
    paths = set()
    for file in files:
        status = file["status"]
        if status not in {"added", "removed", "modified", "changed", "renamed", "copied"}:
            raise ValueError("the comparison contains an unrecognized file status")
        names = [file["filename"]]
        if status in {"renamed", "copied"}:
            names.append(file["previous_filename"])
        if any(not isinstance(name, str) or not name for name in names):
            raise ValueError("the comparison contains an invalid path")
        paths.update(names)
    return sorted(paths)


def plan(event_name, event, repository, request=api):
    if event_name != "pull_request":
        return SUITES, {}, [], "Full validation for this event"
    try:
        pr = event["pull_request"]
        base, head = pr["base"]["sha"], pr["head"]["sha"]
        live = request(f"repos/{repository}/pulls/{int(event['number'])}")
        if (live["base"]["sha"], live["head"]["sha"]) != (base, head):
            return SUITES, {}, [], "PR metadata no longer matches this run"
        labels = {label["name"] for label in live["labels"]}
        requested = sorted(labels & ({"ci:full"} | {f"ci:{suite}" for suite in SUITES}))
        comparison = request(f"repos/{repository}/compare/{base}...{head}?per_page=1")
        paths = compared_paths(comparison, base, live["changed_files"])
    except (KeyError, TypeError, ValueError, OSError, subprocess.SubprocessError):
        return SUITES, {}, [], "PR diff or metadata could not be verified"
    decisions = {path: suites_for(path) for path in paths}
    selected = SUITES if "ci:full" in requested else frozenset().union(
        *decisions.values(), (label[3:] for label in requested),
    )
    return selected, decisions, requested, "PR diff and additive labels"


def write_plan(selected, decisions, requested, reason, outputs, summary):
    for suite in sorted(SUITES):
        print(f"{suite}={str(suite in selected).lower()}", file=outputs)
    print(f"## CI plan\n\n{reason}.\n", file=summary)
    print(f"- Selected suites: {', '.join(sorted(selected)) or 'none'}", file=summary)
    print(f"- Requested labels: {', '.join(requested) or 'none'}\n", file=summary)
    for path, suites in decisions.items():
        # Encode control characters and escape markup in untrusted filenames.
        escaped = html.escape(json.dumps(path)).replace("|", "&#124;").replace("`", "&#96;")
        print(f"- <code>{escaped}</code> → {', '.join(sorted(suites)) or 'no product suite'}", file=summary)


if __name__ == "__main__":
    result = plan(
        os.environ["GITHUB_EVENT_NAME"],
        json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text()),
        os.environ["GITHUB_REPOSITORY"],
    )
    with open(os.environ["GITHUB_OUTPUT"], "a") as outputs, open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
        write_plan(*result, outputs, summary)
