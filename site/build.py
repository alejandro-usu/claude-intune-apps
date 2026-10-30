#!/usr/bin/env python3
"""Build the GitHub Pages site: one page listing every app in apps/, with its download, its
Intune settings and its detection rule or script.

Nothing on the site is written by hand. For each app it reads:
  - app.json                 name, version, dependency, whether it's published as a release
  - README.md                the "## Intune app settings" and "### Detection rule" tables
  - Detect.ps1               shown in full and copied to the site for download, if present
  - logo.png                 shown next to the app, if present (see "App logos" in the README)

Apps are listed newest first: by the date their current version was committed (git log -S on
app.json, following renames), then by version. CI checks out the full history for this.

Downloads come from GitHub, as JSON lines saved by the workflow before this runs:
  --releases   gh api repos/<repo>/releases --paginate --jq '.[]'
  --artifacts  gh api repos/<repo>/actions/artifacts --paginate --jq '.artifacts[]'
Each download is the whole bundle tools/build.py writes to out/<app>/: the .intunewin,
Detect.ps1 (if any) and "Intune settings.txt". Apps with "release": true link to the
<artifact>.zip asset of their GitHub Release (permanent, public). Other apps link to the newest
unexpired CI artifact built on main, which is the same folder (GitHub sign-in needed, expires).

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
import subprocess
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
            # Select, not copy: a page that writes "powershell.exe ... -ExecutionPolicy Bypass" to
            # the clipboard looks exactly like a ClickFix attack, and blockers rightly warn about it.
            cell = (f'<div class="copyable"><code class="selectable">{html.escape(code)}</code>'
                    f'<button class="select" type="button">Select</button></div>')
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


def bundle_contents(app, manifest):
    """The files in the download bundle (see tools/build.py), for listing under the button."""
    setup = os.path.splitext(manifest["setupFile"])[0] + ".intunewin"
    files = [setup]
    if os.path.isfile(os.path.join(build.APPS, app, "Detect.ps1")):
        files.append("Detect.ps1")
    files.append("Intune settings.txt")
    return '<ul class="contents">' + "".join(f"<li>{html.escape(f)}</li>" for f in files) + "</ul>"


def download_block(app, manifest, artifact, releases, artifacts):
    contents = bundle_contents(app, manifest)
    if manifest.get("release"):
        release = next((r for r in releases if r.get("tag_name") == artifact and not r.get("draft")), None)
        assets = (release or {}).get("assets", [])
        bundle = next((a for a in assets if a["name"] == f"{artifact}.zip"), None)
        package = next((a for a in assets if a["name"].endswith(".intunewin")), None)
        if bundle:
            single = (f' <a class="button secondary" href="{html.escape(package["browser_download_url"])}">'
                      f'Just the .intunewin</a>') if package else ""
            return (f'<div class="bundle"><a class="button" href="{html.escape(bundle["browser_download_url"])}">'
                    f'Download {html.escape(bundle["name"])}</a>{single}'
                    f'<span class="size">{human_size(bundle["size"])}</span></div>{contents}'
                    f'<p class="note">From the <a href="{html.escape(release["html_url"])}">{html.escape(artifact)}</a> '
                    f'release. Extract the .zip, then upload the .intunewin to Intune as is.</p>')
        if package:
            digest = (package.get("digest") or "").removeprefix("sha256:")
            sha = f'<p class="note">SHA-256 <code>{html.escape(digest)}</code></p>' if digest else ""
            return (f'<a class="button" href="{html.escape(package["browser_download_url"])}">Download '
                    f'{html.escape(package["name"])}</a> <span class="size">{human_size(package["size"])}</span>'
                    f'<p class="note">From the <a href="{html.escape(release["html_url"])}">{html.escape(artifact)}</a> '
                    f'release. Upload it to Intune as is. The bundle with the settings is added the next time CI '
                    f'builds this app.</p>{sha}')
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
        return (f'<div class="bundle"><a class="button" href="{GITHUB}/actions/runs/{run_id}/artifacts/{a["id"]}">'
                f'Download {html.escape(artifact)}.zip</a>'
                f'<span class="size">{human_size(a.get("size_in_bytes", 0))}</span></div>{contents}'
                f'<p class="note">CI build from <a href="{GITHUB}/actions/runs/{run_id}">this run</a>. Needs a '
                f'GitHub sign-in, and expires {html.escape(expires)}. Extract the .zip, then upload the '
                f'.intunewin to Intune. This app isn\'t published as a release because its installer\'s '
                f'license doesn\'t allow redistributing it.</p>')
    return (f'<p class="missing">No current build of {html.escape(artifact)}. Builds expire after 14 days: '
            f'open <a href="{GITHUB}/actions/workflows/build.yml">Actions → Build Intune packages → Run '
            f'workflow</a> on {BRANCH} and enter <code>{html.escape(app)}</code>. This page updates when that run '
            f'finishes.</p>')


def version_key(version):
    """Natural sort key: "2026.2.3-4" -> (2026, 2, 3, 4), so 3.15.2 sorts above 3.14.7."""
    return tuple(int(p) if p.isdigit() else p for p in re.split(r"[.\-+]", version))


def version_committed(app, version):
    """When the app's current version was committed: the newest commit that added or removed its
    "version" line in app.json, following renames. Empty if git or the history isn't available."""
    try:
        out = subprocess.run(["git", "log", "--follow", "--format=%cI", "-S", f'"version": "{version}"',
                              "--", f"apps/{app}/app.json"], cwd=REPO_DIR, capture_output=True, text=True,
                             check=True).stdout.split()
    except (OSError, subprocess.CalledProcessError):
        return ""
    return out[0] if out else ""


def newest_first(apps):
    def key(app):
        version = build.load_manifest(app)["version"]
        # Not committed yet (a local preview of a new app): treat it as the newest.
        return (version_committed(app, version) or "9999", version_key(version))
    return sorted(apps, key=key, reverse=True)


def logo(app, out_dir):
    """An <img> for apps/<app>/logo.png, copied to the site, or "" if the app has none."""
    path = os.path.join(build.APPS, app, "logo.png")
    if not os.path.isfile(path):
        return ""
    target = os.path.join(out_dir, "apps", app)
    os.makedirs(target, exist_ok=True)
    shutil.copyfile(path, os.path.join(target, "logo.png"))
    return f'<img class="logo" src="apps/{html.escape(app)}/logo.png" alt="">'


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
             f'<div class="app-title">{logo(app, out_dir)}<h2>{html.escape(manifest["name"])}</h2></div>',
             f'<p class="meta">{" · ".join(meta)}</p>',
             '<div class="download">', download_block(app, manifest, artifact, releases, artifacts), "</div>"]

    settings = build.section_table(readme, "## Intune app settings")
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
                  f'<button class="select" type="button" data-select-target="script-{slug(app)}">Select</button></div>',
                  f'<pre id="script-{slug(app)}"><code>{html.escape(script)}</code></pre>']
    rule = build.section_table(readme, "### Detection rule")
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
    for app in newest_first(build.app_names()):
        manifest, artifact, section = app_section(app, releases, artifacts, args.out)
        sections.append(section)
        kind = "Release" if manifest.get("release") else "CI build"
        image = logo(app, args.out)
        index.append(f'<li><a class="{"with-logo" if image else ""}" href="#{slug(app)}">{image}<span class="name">{html.escape(manifest["name"])}</span>'
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
