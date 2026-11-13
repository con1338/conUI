#!/usr/bin/env python3
"""Version watcher: is the addon behind the game or behind EldoUI?

  python3 tools/ci/watch_versions.py           # show what it finds, file nothing
  python3 tools/ci/watch_versions.py --issues  # open an issue for each new finding

Three sources, read once a day by .github/workflows/watch.yml:

* the live WoW: Forever client (Blizzard's public version server, product
  "wowf"): a patch with a higher Interface number than the .toc files means
  the game lists the addon as out of date;
* the test client (product "wow_classic_beta", while it runs a 1.x build):
  the next patch, often days or weeks before it goes live;
* the newest EldoUI release (github.com/Eldodeldo/EldoUI): this fork is
  built on it, and a release for a game patch brings the API fixes too.

The Interface number only says the .toc is behind; whether every part
still works only the game shows (or the EldoUI release for that patch).

--issues needs GITHUB_TOKEN and GITHUB_REPOSITORY (set in GitHub Actions).
Each finding gets one issue with the label LABEL, ever: a closed issue
isn't opened again. If issues can't be opened (turned off for the
repository), the run fails so GitHub sends its failure mail instead.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VERSION_SERVER = "https://us.version.battle.net/v2/products/%s/versions"
LIVE_PRODUCT = "wowf"
TEST_PRODUCT = "wow_classic_beta"
REGIONS = ("eu", "us")
UPSTREAM = "Eldodeldo/EldoUI"
LABEL = "Versions-Check"
USER_AGENT = "WoW-UI-Addon-version-watch"
# GitHub Actions sets GITHUB_API_URL; the tests point it at a stand-in.
API = (os.environ.get("GITHUB_API_URL") or "https://api.github.com").rstrip("/")


# --------------------------------------------------------------------------
# Reading the sources
# --------------------------------------------------------------------------
def fetch(url, token=None, data=None, method=None):
    """GET (or POST data as JSON); returns (status, text). Retries network errors."""
    headers = {"User-Agent": USER_AGENT}
    if url.startswith(API):
        headers["Accept"] = "application/vnd.github+json"
        headers["X-GitHub-Api-Version"] = "2022-11-28"
        if token:
            headers["Authorization"] = "Bearer " + token
    body = None
    if data is not None:
        body = json.dumps(data).encode("utf-8")
        headers["Content-Type"] = "application/json"
    last = None
    for attempt in range(3):
        request = urllib.request.Request(url, data=body, headers=headers, method=method)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.status, response.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as exc:
            if exc.code < 500:
                return exc.code, exc.read().decode("utf-8", "replace")
            last = "HTTP %d" % exc.code
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last = str(getattr(exc, "reason", exc))
        time.sleep(5 * (attempt + 1))
    raise RuntimeError("%s: %s" % (url, last))


def parse_versions(text):
    """Blizzard's versions table ("Region!STRING:0|...|VersionsName!String:0|...")
    -> {region: "1.60.1.70938"}."""
    rows, columns = {}, None
    for line in text.splitlines():
        if not line or line.startswith("##"):
            continue
        cells = line.split("|")
        if columns is None:
            columns = [cell.split("!")[0] for cell in cells]
            continue
        record = dict(zip(columns, cells))
        if record.get("Region") and record.get("VersionsName"):
            rows[record["Region"]] = record["VersionsName"]
    return rows


def interface_of(version):
    """"1.60.1.70938" -> 16001 (major * 10000 + minor * 100 + patch)."""
    match = re.match(r"^(\d+)\.(\d+)\.(\d+)", version or "")
    if not match:
        return None
    major, minor, patch = (int(part) for part in match.groups())
    return major * 10000 + minor * 100 + patch


def client(product):
    """{"version", "interface", "region"} of a product, or None if it has no build."""
    status, text = fetch(VERSION_SERVER % product)
    if status == 404:
        return None
    if status != 200:
        raise RuntimeError("version server, %s: HTTP %d" % (product, status))
    rows = parse_versions(text)
    for region in REGIONS:
        if rows.get(region):
            version = rows[region]
            return {"version": version, "interface": interface_of(version), "region": region}
    return None


def toc_field(path, field):
    with open(path, encoding="utf-8-sig") as fh:
        for line in fh:
            match = re.match(r"##\s*%s\s*:\s*(.+?)\s*$" % re.escape(field), line)
            if match:
                return match[1]
    return None


def addon_state():
    toc = os.path.join(ROOT, "EldoUI", "EldoUI.toc")
    version = toc_field(toc, "Version") or "?"
    numbers = [int(n) for n in re.findall(r"\d+", toc_field(toc, "Interface") or "")]
    return {"version": version, "base": base_version(version), "interface": max(numbers) if numbers else None}


def base_version(version):
    """The EldoUI release a fork version is built on: "0.7.2001-p1" -> "0.7.2001"."""
    return re.sub(r"-p\d+$", "", (version or "").lstrip("vV"))


def version_parts(version):
    match = re.match(r"^\s*[vV]?(\d+(?:\.\d+)*)", version or "")
    return tuple(int(part) for part in match[1].split(".")) if match else None


def newer(a, b):
    """True when version a is newer than version b (missing parts count as 0)."""
    pa, pb = version_parts(a), version_parts(b)
    if not (pa and pb):
        return False
    width = max(len(pa), len(pb))
    return pa + (0,) * (width - len(pa)) > pb + (0,) * (width - len(pb))


def upstream_release(token):
    status, text = fetch("%s/repos/%s/releases/latest" % (API, UPSTREAM), token)
    if status != 200:
        raise RuntimeError("GitHub, newest release of %s: HTTP %d" % (UPSTREAM, status))
    data = json.loads(text)
    return {"tag": data.get("tag_name") or "", "name": data.get("name") or "", "url": data.get("html_url") or "",
            "published": (data.get("published_at") or "")[:10], "body": data.get("body") or ""}


# --------------------------------------------------------------------------
# What is new
# --------------------------------------------------------------------------
def quote_notes(text, limit=4000):
    """Upstream's notes in a fenced block: GitHub renders no mentions or links
    from it, so a copied "@name" notifies nobody."""
    text = text.replace("\r\n", "\n").strip()
    if len(text) > limit:
        text = text[:limit].rsplit("\n", 1)[0] + "\n[…]"
    text = text.replace("````", "'''")
    return "````text\n%s\n````" % text


def findings(addon, live, test, upstream):
    """List of {"key", "title", "body"} for everything the addon is behind on."""
    found = []
    ours = addon["interface"]
    upstream_line = ""
    if upstream:
        upstream_line = "Neueste EldoUI-Version (Upstream): **%s** vom %s." % (
            upstream["tag"].lstrip("vV"), upstream["published"] or "?")
    if live and ours and live["interface"] and live["interface"] > ours:
        found.append({
            "key": "live:%d" % live["interface"],
            "title": "WoW: Forever %s ist live: Interface %d (Addon: %d)" % (
                ".".join(live["version"].split(".")[:3]), live["interface"], ours),
            "body": "\n".join([
                "WoW: Forever hat ein Update: **%s** ist live (Region %s) mit **Interface %d**. "
                "Die .toc-Dateien des Addons stehen auf **%d**." % (
                    live["version"], live["region"].upper(), live["interface"], ours),
                "",
                "**Was das heißt**",
                "- Das Spiel führt die Addons in der AddOn-Liste als veraltet. Mit „Veraltete AddOns laden“ "
                "laufen sie weiter; ob alle Teile noch funktionieren, zeigt erst das Spiel.",
                "- " + (upstream_line or "Die neueste EldoUI-Version ließ sich nicht abrufen.")
                + " Eine neue meldet dieser Wächter in einem eigenen Issue.",
                "",
                "**Vorschlag**",
                "1. Auf die EldoUI-Version für diesen Patch warten und sie übernehmen: sie bringt die nötigen "
                "Anpassungen mit.",
                "2. Kommt keine: `## Interface:` in allen .toc-Dateien auf %d setzen, im Spiel prüfen "
                "(`/eui errors`), neue Version taggen." % live["interface"],
            ]),
        })
    if (test and ours and test["interface"] and test["interface"] > ours and test["version"].startswith("1.")
            and not (live and live["interface"] and test["interface"] <= live["interface"])):
        found.append({
            "key": "test:%d" % test["interface"],
            "title": "WoW: Forever %s im Test-Client: Interface %d kommt" % (
                ".".join(test["version"].split(".")[:3]), test["interface"]),
            "body": "\n".join([
                "Blizzards Test-Client für WoW: Forever (Beta/PTR) hat den Build **%s** mit **Interface %d**; "
                "live und im Addon ist es noch %d." % (
                    test["version"], test["interface"], live["interface"] if live else ours),
                "",
                "Noch nichts zu tun: Das ist der nächste Patch, meist Tage oder Wochen bevor er live geht. "
                "Wer einen Test-Zugang hat, kann das Addon dort schon ausprobieren. Geht der Patch live, "
                "kommt ein eigenes Issue.",
            ]),
        })
    if upstream and newer(upstream["tag"], addon["base"]):
        version = upstream["tag"].lstrip("vV")
        lines = [
            "EldoUI **%s** ist erschienen (veröffentlicht %s): %s" % (version, upstream["published"] or "?", upstream["url"]),
            "",
            "Dieser Fork baut auf EldoUI %s auf (Version %s)." % (addon["base"], addon["version"]),
            "",
            "**Übernehmen**",
            "1. Die Ordner `EldoUI*/` aus dem Release-ZIP unverändert übernehmen und die Änderungen des Forks "
            "darauf wieder einspielen (Sprachpaket, Pinnwand, Fehlerbehebungen aus `review/fehler.md`, Links, "
            "Versions-Endung).",
            "2. Version auf `%s-p1` setzen, die Prüfungen müssen grün sein, im Spiel testen." % version,
            "3. Tag `v%s-p1` pushen: Der Release-Workflow baut das ZIP." % version,
        ]
        if upstream["body"].strip():
            lines += ["", "<details><summary>Release-Notizen von EldoUI %s</summary>" % version, "",
                      quote_notes(upstream["body"]), "", "</details>"]
        found.append({"key": "upstream:%s" % version,
                      "title": "EldoUI %s ist erschienen (Fork: %s)" % (version, addon["version"]),
                      "body": "\n".join(lines)})
    for item in found:
        item["body"] += "\n\n<!-- version-watch:%s -->\n_Gemeldet von `.github/workflows/watch.yml`._" % item["key"]
    return found


# --------------------------------------------------------------------------
# Issues
# --------------------------------------------------------------------------
def filed_keys(repo, token):
    keys, page = set(), 1
    while True:
        status, text = fetch("%s/repos/%s/issues?labels=%s&state=all&per_page=100&page=%d"
                             % (API, repo, LABEL, page), token)
        if status == 410:
            raise RuntimeError("issues are turned off for %s" % repo)
        if status != 200:
            raise RuntimeError("GitHub, issues of %s: HTTP %d" % (repo, status))
        batch = json.loads(text)
        for issue in batch:
            keys.update(re.findall(r"<!-- version-watch:(\S+) -->", issue.get("body") or ""))
        if len(batch) < 100:
            return keys
        page += 1


def file_issue(repo, token, item):
    fetch("%s/repos/%s/labels" % (API, repo), token, method="POST",
          data={"name": LABEL, "color": "1d76db", "description": "Neue Spiel- oder EldoUI-Version (Versionswächter)"})
    status, text = fetch("%s/repos/%s/issues" % (API, repo), token, method="POST",
                         data={"title": item["title"], "body": item["body"], "labels": [LABEL]})
    if status != 201:
        raise RuntimeError("GitHub, new issue: HTTP %d %s" % (status, text[:200]))
    return json.loads(text).get("html_url")


# --------------------------------------------------------------------------
def main():
    open_issues = "--issues" in sys.argv[1:]
    token = os.environ.get("GITHUB_TOKEN") or None
    repo = os.environ.get("GITHUB_REPOSITORY")
    if open_issues and not (token and repo):
        sys.exit("--issues needs GITHUB_TOKEN and GITHUB_REPOSITORY")

    problems = []
    addon = addon_state()

    def read(label, reader, *args):
        try:
            return reader(*args)
        except (RuntimeError, ValueError) as exc:
            problems.append("%s: %s" % (label, exc))
            return None

    live = read("live client", client, LIVE_PRODUCT)
    test = read("test client", client, TEST_PRODUCT)
    upstream = read("EldoUI release", upstream_release, token)

    summary = [
        "| Quelle | Stand |", "|---|---|",
        "| Addon | %s, Interface %s |" % (addon["version"], addon["interface"]),
        "| WoW: Forever live | %s |" % ("%s, Interface %s" % (live["version"], live["interface"]) if live else "nicht abrufbar"),
        "| Test-Client | %s |" % ("%s, Interface %s" % (test["version"], test["interface"]) if test else "keiner / nicht abrufbar"),
        "| EldoUI (Upstream) | %s |" % ("%s vom %s" % (upstream["tag"], upstream["published"]) if upstream else "nicht abrufbar"),
    ]
    found = findings(addon, live, test, upstream)
    print("\n".join(summary))
    print()
    if not found:
        print("Nichts Neues: das Addon ist auf dem Stand des Spiels und von EldoUI."
              if not problems else "Nichts Neues bei den Quellen, die sich lesen ließen.")
    filed = []
    if found and open_issues:
        try:
            known = filed_keys(repo, token)
            for item in found:
                if item["key"] in known:
                    print("schon gemeldet: %s" % item["title"])
                    continue
                url = file_issue(repo, token, item)
                filed.append("[%s](%s)" % (item["title"], url))
                print("Issue: %s\n  %s" % (item["title"], url))
        except RuntimeError as exc:
            problems.append("issues: %s" % exc)
            for item in found:
                print("::warning title=Versionswächter::%s" % item["title"])
    elif found:
        for item in found:
            print("NEU: %s\n\n%s\n" % (item["title"], item["body"]))

    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with open(step_summary, "a", encoding="utf-8") as fh:
            fh.write("### Versionswächter\n\n" + "\n".join(summary) + "\n\n")
            for item in found:
                fh.write("- %s\n" % item["title"])
            for link in filed:
                fh.write("- neues Issue: %s\n" % link)
            for problem in problems:
                fh.write("- **Fehler:** %s\n" % problem)
    for problem in problems:
        print("::error title=Versionswächter::%s" % problem)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
