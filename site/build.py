#!/usr/bin/env python3
"""Build the GitHub Pages site: one page listing every app in apps/, with its download, its
Intune settings and its detection rule or script.

Nothing on the site is written by hand. For each app it reads:
  - app.json                 name, version, dependency, whether it's published as a release
  - README.md                the "## Intune app settings" and "### Detection rule" tables
  - Detect.ps1               shown in full and copied to the site for download, if present

Downloads come from GitHub, as JSON lines saved by the workflow before this runs:
  --releases   gh api repos/<repo>/releases --paginate --jq '.[]'
  --artifacts  gh api repos/<repo>/actions/artifacts --paginate --jq '.artifacts[]'
Apps with "release": true link to their GitHub Release asset (permanent, public). Other apps
link to the newest unexpired CI artifact built on main (GitHub sign-in needed, expires).

Usage:
    python3 site/build.py [--releases FILE] [--artifacts FILE] [--out _site]
Without the two files it still builds, showing every download as not available.
"""
import argparse
import datetime
import html
import json
import os
import re
import shutil
import sys

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(REPO_DIR, "tools"))
import build  # noqa: E402

SITE_DIR = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("GITHUB_REPOSITORY", "alejandro-usu/claude-intune-apps")
BRANCH = "main"
GITHUB = f"https://github.com/{REPO}"


def read_json_lines(path):
    if not path or not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def section_table(markdown, heading):
    """Rows of the first two-column table after `heading`, as (key, value) markdown strings."""
    lines = markdown.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == heading)
    except StopIteration:
        return []
    rows, in_table = [], False
    for line in lines[start + 1:]:
        stripped = line.strip()
        if stripped.startswith("|"):
            in_table = True
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            key, value = cells[0], "|".join(cells[1:]).strip()
            if set(key) <= set("-: ") or (not rows and key in ("Setting", "Field")):
                continue  # separator or header row
            rows.append((key, value))
        elif in_table or stripped.startswith("#"):
            break
    return rows


def inline(text, base):
    """Render the inline markdown the READMEs use: `code`, **bold** and [links](url).
    Relative links resolve against `base`, the app folder on GitHub."""
    out, pos = [], 0
    link = re.compile(r"\[((?:[^\]`]|`[^`]*`)+)\]\(([^)\s]+)\)")
    for m in link.finditer(text):
        out.append(inline_plain(text[pos:m.start()]))
        url = m.group(2)
        if not re.match(r"[a-z]+://", url):
            url = f"{base}/{url}"
        out.append(f'<a href="{html.escape(url)}">{inline_plain(m.group(1))}</a>')
        pos = m.end()
    out.append(inline_plain(text[pos:]))
    return "".join(out)


def inline_plain(text):
    parts = re.split(r"(`[^`]*`)", text)
    out = []
    for part in parts:
        if part.startswith("`") and part.endswith("`") and len(part) > 1:
            out.append(f"<code>{html.escape(part[1:-1])}</code>")
        else:
            out.append(re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", html.escape(part, quote=False)))
    return "".join(out)


def single_code(value):
    """The code text if the whole value is one `code` span (a command, a path), else None."""
    m = re.fullmatch(r"`([^`]+)`", value.strip())
    return m.group(1) if m else None


def settings_table(rows, base):
    out = ['<table class="settings"><tbody>']
    for key, value in rows:
        code = single_code(value)
        if code is not None:
            cell = (f'<div class="copyable"><code>{html.escape(code)}</code>'
                    f'<button class="copy" type="button" data-copy="{html.escape(code)}">Copy</button></div>')
        else:
            cell = inline(value, base)
        out.append(f"<tr><th scope=\"row\">{inline(key, base)}</th><td>{cell}</td></tr>")
    out.append("</tbody></table>")
    return "\n".join(out)


def human_size(n):
    for unit in ("bytes", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:,.0f} {unit}" if unit == "bytes" else f"{n:,.1f} {unit}"
        n /= 1024


def download_block(app, manifest, artifact, releases, artifacts):
    if manifest.get("release"):
        release = next((r for r in releases if r.get("tag_name") == artifact and not r.get("draft")), None)
        asset = next((a for a in (release or {}).get("assets", []) if a["name"].endswith(".intunewin")), None)
        if asset:
            digest = (asset.get("digest") or "").removeprefix("sha256:")
            sha = f'<p class="note">SHA-256 <code>{html.escape(digest)}</code></p>' if digest else ""
            return (f'<a class="button" href="{html.escape(asset["browser_download_url"])}">Download '
                    f'{html.escape(asset["name"])}</a> <span class="size">{human_size(asset["size"])}</span>'
                    f'<p class="note">From the <a href="{html.escape(release["html_url"])}">{html.escape(artifact)}</a> '
                    f'release. Upload it to Intune as is.</p>{sha}')
        return (f'<p class="missing">No release for {html.escape(artifact)} yet. CI creates it the next '
                f'time it builds this app on {BRANCH}.</p>')

    current = [a for a in artifacts
               if a.get("name") == artifact and not a.get("expired")
               and (a.get("workflow_run") or {}).get("head_branch") == BRANCH]
    current.sort(key=lambda a: a.get("created_at", ""), reverse=True)
    if current:
        a = current[0]
        run_id = a["workflow_run"]["id"]
        expires = a.get("expires_at", "")[:10]
        return (f'<a class="button" href="{GITHUB}/actions/runs/{run_id}/artifacts/{a["id"]}">Download '
                f'{html.escape(artifact)}.zip</a> <span class="size">{human_size(a.get("size_in_bytes", 0))}</span>'
                f'<p class="note">CI build from <a href="{GITHUB}/actions/runs/{run_id}">this run</a>. Needs a '
                f'GitHub sign-in, and expires {html.escape(expires)}. Extract the .zip before uploading to '
                f'Intune. This app isn\'t published as a release because its installer\'s license doesn\'t '
                f'allow redistributing it.</p>')
    return (f'<p class="missing">No current build of {html.escape(artifact)}. Builds expire after 14 days: '
            f'open <a href="{GITHUB}/actions/workflows/build.yml">Actions → Build Intune packages → Run '
            f'workflow</a> on {BRANCH} and enter <code>{html.escape(app)}</code>. This page updates when that run '
            f'finishes.</p>')


def slug(app):
    return re.sub(r"[^a-z0-9]+", "-", app.lower()).strip("-")


def app_section(app, releases, artifacts, out_dir):
    manifest = build.load_manifest(app)
    artifact = build.artifact_name(app, manifest)
    app_dir = os.path.join(build.APPS, app)
    base = f"{GITHUB}/blob/{BRANCH}/apps/{app}"
    with open(os.path.join(app_dir, "README.md"), encoding="utf-8") as f:
        readme = f.read()

    meta = [f"<code>{html.escape(app)}</code>", f"version {html.escape(manifest['version'])}"]
    dep = manifest.get("dependsOn")
    if dep:
        meta.append(f'depends on <a href="#{slug(dep)}">{html.escape(dep)}</a>')

    parts = [f'<section class="app" id="{slug(app)}">',
             f"<h2>{html.escape(manifest['name'])}</h2>",
             f'<p class="meta">{" · ".join(meta)}</p>',
             '<div class="download">', download_block(app, manifest, artifact, releases, artifacts), "</div>"]

    settings = section_table(readme, "## Intune app settings")
    if settings:
        parts += ["<h3>Intune app settings</h3>", settings_table(settings, base)]

    detect = os.path.join(app_dir, "Detect.ps1")
    if os.path.isfile(detect):
        with open(detect, encoding="utf-8-sig") as f:
            script = f.read()
        target = os.path.join(out_dir, "apps", app)
        os.makedirs(target, exist_ok=True)
        shutil.copyfile(detect, os.path.join(target, "Detect.ps1"))
        parts += ["<h3>Detection script</h3>",
                  '<p class="note">Upload as a custom detection script, with "Run script as 32-bit '
                  'process" set to <strong>No</strong>.</p>',
                  '<div class="script-actions">'
                  f'<a class="button secondary" href="apps/{html.escape(app)}/Detect.ps1" download>Download Detect.ps1</a>'
                  f'<button class="copy" type="button" data-copy-target="script-{slug(app)}">Copy</button></div>',
                  f'<pre id="script-{slug(app)}"><code>{html.escape(script)}</code></pre>']
    rule = section_table(readme, "### Detection rule")
    if rule:
        parts += ["<h3>Detection rule</h3>", settings_table(rule, base)]

    parts += [f'<p class="more"><a href="{base}/README.md">Full README</a>: what the install does, '
              f'updating, troubleshooting.</p>', "</section>"]
    return manifest, artifact, "\n".join(parts)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--releases", help="JSON lines of GitHub releases")
    parser.add_argument("--artifacts", help="JSON lines of GitHub Actions artifacts")
    parser.add_argument("--out", default=os.path.join(REPO_DIR, "_site"))
    args = parser.parse_args()

    releases = read_json_lines(args.releases)
    artifacts = read_json_lines(args.artifacts)
    shutil.rmtree(args.out, ignore_errors=True)
    os.makedirs(args.out)

    sections, index = [], []
    for app in build.app_names():
        manifest, artifact, section = app_section(app, releases, artifacts, args.out)
        sections.append(section)
        kind = "Release" if manifest.get("release") else "CI build"
        index.append(f'<li><a href="#{slug(app)}"><span class="name">{html.escape(manifest["name"])}</span>'
                     f'<span class="tag">{kind}</span><span class="artifact">{html.escape(artifact)}</span></a></li>')

    with open(os.path.join(SITE_DIR, "template.html"), encoding="utf-8") as f:
        page = f.read()
    generated = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    page = (page.replace("{{repo_url}}", GITHUB)
                .replace("{{index}}", "\n".join(index))
                .replace("{{apps}}", "\n".join(sections))
                .replace("{{generated}}", generated))
    with open(os.path.join(args.out, "index.html"), "w", encoding="utf-8") as f:
        f.write(page)
    # Serve files as they are, without Jekyll.
    open(os.path.join(args.out, ".nojekyll"), "w").close()
    print(f"Wrote {args.out} ({len(sections)} apps)")


if __name__ == "__main__":
    main()
