#!/usr/bin/env python3
"""Offline tests of the version watcher (tools/ci/watch_versions.py): no network.

  python3 tools/ci/test_watch_versions.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True
import watch_versions as W  # noqa: E402

failures = 0
count = 0


def check(name, got, want):
    global failures, count
    count += 1
    if got != want:
        failures += 1
        print("FAIL %s\n  got:  %r\n  want: %r" % (name, got, want))


# The version server's table, as it answers for wowf.
TABLE = """Region!STRING:0|BuildConfig!HEX:16|CDNConfig!HEX:16|KeyRing!HEX:16|BuildId!DEC:4|VersionsName!String:0|ProductConfig!HEX:16
## seqn = 4135569
us|3627b099867bfde3e37a17cf44f69cdc|3363ac656da5f261cdc675ab28b2744c||70938|1.60.1.70938|0d21f2f209a32c57f8c9b838cb35fd0a
eu|3627b099867bfde3e37a17cf44f69cdc|3363ac656da5f261cdc675ab28b2744c||70999|1.60.2.70999|0d21f2f209a32c57f8c9b838cb35fd0a
"""
check("parse table", W.parse_versions(TABLE), {"us": "1.60.1.70938", "eu": "1.60.2.70999"})
check("parse empty", W.parse_versions(""), {})
check("interface 1.60.1", W.interface_of("1.60.1.70938"), 16001)
check("interface 1.61.0", W.interface_of("1.61.0.71000"), 16100)
check("interface retail", W.interface_of("12.1.7.70892"), 120107)
check("interface junk", W.interface_of("dev"), None)

check("base of fork", W.base_version("0.7.2001-p1"), "0.7.2001")
check("base of upstream", W.base_version("v0.7.2001"), "0.7.2001")
check("newer patch", W.newer("v0.7.2002", "0.7.2001"), True)
check("same", W.newer("v0.7.2001", "0.7.2001"), False)
check("older", W.newer("0.7.2000", "0.7.2001"), False)
check("newer minor", W.newer("0.8.0", "0.7.2001"), True)
check("more parts", W.newer("0.7.2001.1", "0.7.2001"), True)
check("not a version", W.newer("dev", "0.7.2001"), False)

ADDON = {"version": "0.7.2001-p1", "base": "0.7.2001", "interface": 16001}


def build(version, region="eu"):
    return {"version": version, "interface": W.interface_of(version), "region": region}


def release(tag, body=""):
    return {"tag": tag, "name": tag, "url": "https://example.invalid/" + tag, "published": "2026-11-20", "body": body}


def keys(found):
    return [item["key"] for item in found]


same = W.findings(ADDON, build("1.60.1.70938"), build("1.60.1.70532"), release("v0.7.2001"))
check("nothing new", keys(same), [])
check("hotfix build, same interface", keys(W.findings(ADDON, build("1.60.1.71500"), None, None)), [])

patch = W.findings(ADDON, build("1.61.0.71000"), build("1.61.0.71000"), release("v0.7.2001"))
check("patch live", keys(patch), ["live:16100"])
check("patch title", patch[0]["title"], "WoW: Forever 1.61.0 ist live: Interface 16100 (Addon: 16001)")
check("patch body has marker", "<!-- version-watch:live:16100 -->" in patch[0]["body"], True)
check("patch body names upstream", "0.7.2001" in patch[0]["body"], True)

coming = W.findings(ADDON, build("1.60.1.70938"), build("1.61.0.70990"), None)
check("patch on test client", keys(coming), ["test:16100"])
check("test title", coming[0]["title"], "WoW: Forever 1.61.0 im Test-Client: Interface 16100 kommt")
# The test product may run another game's beta (Classic Era 1.15, Mists 5.5).
check("other beta (1.15)", keys(W.findings(ADDON, build("1.60.1.70938"), build("1.15.9.70576"), None)), [])
check("other beta (5.5)", keys(W.findings(ADDON, build("1.60.1.70938"), build("5.5.4.70631"), None)), [])
check("no live read", keys(W.findings(ADDON, None, build("1.61.0.70990"), None)), ["test:16100"])

update = W.findings(ADDON, build("1.60.1.70938"), None, release("v0.7.2002", "Highlights\n- @someone fixed it\n````\nend"))
check("upstream release", keys(update), ["upstream:0.7.2002"])
check("upstream title", update[0]["title"], "EldoUI 0.7.2002 ist erschienen (Fork: 0.7.2001-p1)")
body = update[0]["body"]
check("notes fenced", "````text\nHighlights" in body, True)
check("inner fence defused", body.count("````"), 2)
check("next fork version", "0.7.2002-p1" in body, True)
check("older upstream", keys(W.findings(ADDON, None, None, release("v0.7.2000"))), [])

both = W.findings(ADDON, build("1.61.0.71000"), None, release("v0.7.2002"))
check("patch and release", keys(both), ["live:16100", "upstream:0.7.2002"])

long_notes = W.quote_notes("line\n" * 2000, limit=100)
check("notes cut", long_notes.endswith("[…]\n````"), True)
check("notes cut short", len(long_notes) < 200, True)

state = W.addon_state()
# The stand-in's EldoUI release is one patch after the addon's own base
# version, so the run below finds it new whatever version the fork is on.
NEXT = ".".join(state["base"].split(".")[:-1] + [str(int(state["base"].split(".")[-1]) + 1)])
check("addon state reads the toc", (state["base"] == W.base_version(state["version"]), isinstance(state["interface"], int)),
      (True, True))


# --------------------------------------------------------------------------
# A whole run with --issues against a stand-in for both servers.
# --------------------------------------------------------------------------
import contextlib  # noqa: E402
import http.server  # noqa: E402
import io  # noqa: E402
import json  # noqa: E402
import threading  # noqa: E402


class Stand(http.server.BaseHTTPRequestHandler):
    issues_status = 200
    filed = []
    seen_auth = {}

    def log_message(self, *_):
        pass

    def answer(self, status, payload, text=False):
        data = payload.encode() if text else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        Stand.seen_auth[self.path.split("?")[0]] = self.headers.get("Authorization")
        if self.path == "/versions/wowf":
            return self.answer(200, TABLE.replace("1.60.2.70999", "1.61.0.71000"), text=True)
        if self.path.startswith("/versions/"):
            return self.answer(404, "", text=True)
        if self.path == "/repos/Eldodeldo/EldoUI/releases/latest":
            return self.answer(200, {"tag_name": "v" + NEXT, "html_url": "https://example.invalid/r",
                                     "published_at": "2026-11-20T10:00:00Z", "body": "Notes"})
        if self.path.startswith("/repos/me/fork/issues?"):
            if Stand.issues_status != 200:
                return self.answer(Stand.issues_status, {"message": "Issues are disabled for this repo"})
            return self.answer(200, [{"body": "old\n<!-- version-watch:upstream:%s -->" % NEXT}])
        self.answer(404, {})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.path == "/repos/me/fork/labels":
            return self.answer(422, {"message": "already_exists"})
        if self.path == "/repos/me/fork/issues":
            Stand.filed.append(body)
            return self.answer(201, {"html_url": "https://example.invalid/issues/%d" % len(Stand.filed)})
        self.answer(404, {})


os.environ["no_proxy"] = os.environ["NO_PROXY"] = "127.0.0.1,localhost"
server = http.server.HTTPServer(("127.0.0.1", 0), Stand)
threading.Thread(target=server.serve_forever, daemon=True).start()
base = "http://127.0.0.1:%d" % server.server_port
W.API, W.VERSION_SERVER = base, base + "/versions/%s"
os.environ.update({"GITHUB_TOKEN": "test-token", "GITHUB_REPOSITORY": "me/fork"})
os.environ.pop("GITHUB_STEP_SUMMARY", None)


def run():
    sys.argv = ["watch_versions.py", "--issues"]
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = W.main()
    return code, out.getvalue()


code, out = run()
check("run: exit code", code, 0)
check("run: one new issue (the patch)", [issue["title"] for issue in Stand.filed],
      ["WoW: Forever 1.61.0 ist live: Interface 16100 (Addon: %d)" % state["interface"]])
check("run: issue has the label", Stand.filed[0]["labels"] if Stand.filed else None, [W.LABEL])
check("run: release already filed, skipped", "schon gemeldet: EldoUI %s" % NEXT in out, True)
check("run: token sent to GitHub", Stand.seen_auth.get("/repos/Eldodeldo/EldoUI/releases/latest"), "Bearer test-token")
check("run: no token to Blizzard", Stand.seen_auth.get("/versions/wowf"), None)

Stand.filed.clear()
Stand.issues_status = 410
code, out = run()
check("issues off: run fails", code, 1)
check("issues off: says why", "issues are turned off for me/fork" in out, True)
check("issues off: nothing filed", Stand.filed, [])
server.shutdown()

print("%d of %d checks passed" % (count - failures, count))
sys.exit(1 if failures else 0)
