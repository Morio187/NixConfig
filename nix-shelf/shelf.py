#!/usr/bin/env python3
"""Nix Shelf: browse nixpkgs as cards, install/uninstall via configuration.nix, test via `nix run`.

Run: python3 nix-shelf/shelf.py   (opens a Chrome app window, Ctrl+C to stop)
"""
import json, os, re, shutil, subprocess, sys, webbrowser
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse, parse_qs

HERE = Path(__file__).resolve().parent
FLAKE = HERE.parent                       # ~/NixConfig
CONF = FLAKE / "configuration.nix"
HOST = "lk"                               # nixosConfigurations.<HOST>
CACHE = Path.home() / ".cache/nix-shelf"
INDEX = CACHE / "packages.json"
BACKUP = CACHE / "configuration.nix.bak"
SCHEME = Path.home() / ".local/state/caelestia/scheme.json"
ATTR = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.+-]*$")   # trust boundary: only plain attr paths reach nix/shell
PKG_LINE = re.compile(r"^    ([A-Za-z0-9_][A-Za-z0-9_.+-]*)\s*(#.*)?$")
START = "environment.systemPackages = with pkgs; ["
TAG = "  # added by nix-shelf"


# ---------- configuration.nix editing ----------

def pkg_block(text):
    """(start, end) offsets of the systemPackages list body."""
    s = text.index(START) + len(START)
    return s, text.index("\n  ];", s)

def installed():
    text = CONF.read_text()
    s, e = pkg_block(text)
    return [m.group(1) for line in text[s:e].splitlines() if (m := PKG_LINE.match(line))]

def edited_config(attr, add):
    text = CONF.read_text()
    s, e = pkg_block(text)
    body = text[s:e].splitlines(keepends=True)
    if add:
        if attr in installed():
            raise ValueError(f"{attr} is already in configuration.nix")
        body.append(f"\n    {attr}{TAG}")
    else:
        kept = [l for l in body if not ((m := PKG_LINE.match(l.rstrip("\n"))) and m.group(1) == attr)]
        if len(kept) == len(body):
            raise ValueError(f"{attr} is not a plain entry in configuration.nix (edit it by hand)")
        body = kept
    return text[:s] + "".join(body).rstrip("\n") + text[e:]


# ---------- nix ----------

def build_index():
    print("Indexing nixpkgs (≈1 min, once)…", flush=True)
    out = subprocess.run(["nix", "search", "--inputs-from", str(FLAKE), "nixpkgs", "^", "--json"],
                         capture_output=True, text=True, check=True).stdout
    pkgs = [[k.split(".", 2)[2], v["description"], v["version"]] for k, v in json.loads(out).items()]
    CACHE.mkdir(parents=True, exist_ok=True)
    INDEX.write_text(json.dumps(pkgs, separators=(",", ":")))

META_FN = """m: let lic = x: if builtins.isAttrs x then x.fullName or x.spdxId or "?" else toString x; in {
  description = m.description or ""; longDescription = m.longDescription or "";
  homepage = m.homepage or ""; mainProgram = m.mainProgram or "";
  license = if builtins.isList (m.license or null) then map lic m.license else lic (m.license or "unknown");
  unfree = !(m.license.free or true); }"""

def meta(attr):
    attr = attr.removeprefix("pkgsUnstable.")
    r = subprocess.run(["nix", "eval", "--json", "--inputs-from", str(FLAKE), f"nixpkgs#{attr}.meta", "--apply", META_FN],
                       capture_output=True, text=True)
    if r.returncode:
        raise ValueError(r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "nix eval failed")
    return json.loads(r.stdout)

def terminal(script, *args):
    """Run a shell script in a visible foot window; args arrive as $1.. (never interpolated)."""
    subprocess.Popen(["foot", "--title", "Nix Shelf", "sh", "-c", script + '\necho; read -p "Press Enter to close" _', "_", *args],
                     start_new_session=True)

def rebuild(new_text):
    CACHE.mkdir(parents=True, exist_ok=True)
    shutil.copy(CONF, BACKUP)
    CONF.write_text(new_text)
    # failed rebuild restores the previous configuration.nix so the config never stays broken
    terminal('sudo nixos-rebuild switch --flake "$1" || { cp "$2" "$3"; echo; echo "Rebuild failed: configuration.nix restored."; }',
             f"{FLAKE}#{HOST}", str(BACKUP), str(CONF))

def test(attr):
    attr = attr.removeprefix("pkgsUnstable.")
    terminal('export NIXPKGS_ALLOW_UNFREE=1; nix run --impure --inputs-from "$1" "nixpkgs#$2" || {'
             ' echo; echo "No runnable program, opening a shell with $2 available (exit to leave)";'
             ' nix shell --impure --inputs-from "$1" "nixpkgs#$2" -c "${SHELL:-sh}"; }',
             str(FLAKE), attr)


# ---------- HTTP ----------

class Handler(BaseHTTPRequestHandler):
    def send(self, code, body, ctype="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def ours(self):
        # blocks other websites (DNS rebinding / CSRF) from driving rebuilds
        return self.headers.get("Host") == f"127.0.0.1:{self.server.server_port}"

    def do_GET(self):
        if not self.ours():
            return self.send(403, {"error": "forbidden"})
        u = urlparse(self.path)
        q = parse_qs(u.query)
        try:
            if u.path == "/":
                self.send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
            elif u.path == "/api/packages":
                self.send(200, INDEX.read_bytes())
            elif u.path == "/api/scheme":
                self.send(200, SCHEME.read_bytes() if SCHEME.exists() else b"{}")
            elif u.path == "/api/installed":
                self.send(200, installed())
            elif u.path == "/api/meta":
                attr = q.get("attr", [""])[0]
                if not ATTR.match(attr):
                    return self.send(400, {"error": "bad attribute name"})
                self.send(200, meta(attr))
            else:
                self.send(404, {"error": "not found"})
        except ValueError as e:
            self.send(400, {"error": str(e)})

    def do_POST(self):
        if not self.ours() or self.headers.get("X-Shelf") != "1":
            return self.send(403, {"error": "forbidden"})
        attr = parse_qs(urlparse(self.path).query).get("attr", [""])[0]
        if not ATTR.match(attr):
            return self.send(400, {"error": "bad attribute name"})
        action = urlparse(self.path).path
        try:
            if action == "/api/install":
                rebuild(edited_config(attr, True))
            elif action == "/api/uninstall":
                rebuild(edited_config(attr, False))
            elif action == "/api/test":
                test(attr)
            else:
                return self.send(404, {"error": "not found"})
            self.send(200, {"ok": True})
        except ValueError as e:
            self.send(400, {"error": str(e)})

    def log_message(self, *a):
        pass


def selftest():
    global CONF
    import tempfile
    real = CONF
    with tempfile.TemporaryDirectory() as d:
        CONF = Path(d) / "c.nix"
        CONF.write_text(real.read_text())
        before = installed()
        assert "git" in before and "pkgsUnstable.firefox" in before and "foot" in before
        CONF.write_text(edited_config("hello", True))
        assert installed() == before + ["hello"]
        CONF.write_text(edited_config("hello", False))
        assert CONF.read_text() == real.read_text()
        for bad in ("git", "nope"):
            try: edited_config(bad, bad == "git"); assert False
            except ValueError: pass
        assert not ATTR.match("a;rm -rf ~") and not ATTR.match("$(x)")
    CONF = real
    print("selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest(); sys.exit()
    if not INDEX.exists() or "--reindex" in sys.argv:
        build_index()
    srv = HTTPServer(("127.0.0.1", 0), Handler)
    url = f"http://127.0.0.1:{srv.server_port}/"
    print(f"Nix Shelf on {url}  (Ctrl+C to stop)", flush=True)
    if "--no-open" not in sys.argv:
        chrome = shutil.which("google-chrome-stable") or shutil.which("google-chrome")
        subprocess.Popen([chrome, f"--app={url}"], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) if chrome else webbrowser.open(url)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
