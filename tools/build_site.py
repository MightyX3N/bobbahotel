#!/usr/bin/env python3
"""Builds Bobba Hotel's website (playbobba.com) into website/.

    python3 tools/build_site.py

Sources: website-src/ (the landing page, the style, pictures), docs/*.md (the docs; their front matter has
title, order, description), CHANGELOG.md and ROADMAP.md. The output in website/ is what GitHub Pages
serves (.github/workflows/pages.yml); build and commit it with the sources.
Needs: pip install markdown pygments
"""
import html
import os
import re
import shutil

import markdown
from markdown.extensions.toc import TocExtension

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "website-src")
OUT = os.path.join(ROOT, "website")
REPO = "https://github.com/MightyX3N/bobbahotel"

KEY_SVG = ('<svg viewBox="0 0 24 24" fill="none" stroke="#0f1a2e" stroke-width="2.6" stroke-linecap="round" '
           'stroke-linejoin="round"><circle cx="8" cy="15" r="4"/><path d="M11 12l8-8M16 7l3 3M14 9l2 2"/></svg>')
GH_SVG = ('<svg viewBox="0 0 16 16"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 '
          '0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 '
          '1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15'
          '-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82'
          '.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 '
          '1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>')
MENU_SVG = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round">'
            '<path d="M4 7h16M4 12h16M4 17h16"/></svg>')


def page(title, body, root, active, description, extra_head=""):
    """A whole page: root is the way back to the site's top ("" or "../")."""
    def nav(href, label, key):
        on = ' class="on"' if key == active else ""
        return f'<a href="{root}{href}"{on}>{label}</a>'
    full_title = "Bobba Hotel" if title == "Bobba Hotel" else f"{title} - Bobba Hotel"
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(full_title)}</title>
<meta name="description" content="{html.escape(description)}">
<meta property="og:title" content="{html.escape(full_title)}">
<meta property="og:description" content="{html.escape(description)}">
<meta property="og:image" content="https://playbobba.com/img/room.webp">
<meta name="theme-color" content="#0f1a2e">
<link rel="icon" href="{root}favicon.svg" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;600&family=Lilita+One&family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="{root}style.css">
{extra_head}</head>
<body>
<header class="bar">
	<div class="wrap">
		<a class="logo" href="{root}index.html"><span class="key">{KEY_SVG}</span>Bobba Hotel</a>
		<button class="menu-btn" aria-label="Menu" onclick="document.querySelector('.nav').classList.toggle('open')">{MENU_SVG}</button>
		<nav class="nav">
			{nav("index.html#why", "Why Bobba", "why")}
			{nav("docs/getting-started.html", "Docs", "docs")}
			{nav("changelog.html", "Changelog", "changelog")}
			{nav("roadmap.html", "Roadmap", "roadmap")}
			<a class="gh" href="{REPO}">{GH_SVG}GitHub</a>
		</nav>
	</div>
</header>
<main>
{body}
</main>
<footer class="foot">
	<div class="wrap">
		<div>Bobba Hotel is free software (GPL-3.0), a fan project not affiliated with Habbo or Sulake.</div>
		<div class="links">
			<a href="{root}docs/getting-started.html">Docs</a>
			<a href="{root}changelog.html">Changelog</a>
			<a href="{root}roadmap.html">Roadmap</a>
			<a href="{REPO}">GitHub</a>
		</div>
	</div>
</footer>
</body>
</html>
"""


def front_matter(text):
    meta = {}
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if m:
        for line in m.group(1).splitlines():
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip()
        text = text[m.end():]
    return meta, text


def md(text):
    conv = markdown.Markdown(extensions=[
        "tables", "fenced_code", "codehilite", "attr_list", "sane_lists",
        TocExtension(permalink="#", permalink_class="anchor", toc_depth="2-3"),
    ], extension_configs={"codehilite": {"guess_lang": False, "css_class": "hl"}})
    body = conv.convert(text)
    # tables scroll sideways on a phone
    body = body.replace("<table>", '<div class="table-wrap"><table>').replace("</table>", "</table></div>")
    return body, conv.toc_tokens


def toc_html(tokens):
    out = []
    for t in tokens:
        out.append(f'<a href="#{t["id"]}">{t["name"]}</a>')
        for c in t.get("children", []):
            out.append(f'<a class="l3" href="#{c["id"]}">{c["name"]}</a>')
    return "\n".join(out)


def pygments_css():
    from pygments.formatters import HtmlFormatter
    return HtmlFormatter(style="github-dark").get_style_defs(".hl") + "\n.hl { background: transparent !important; }\n.hl pre { margin: 0; }\n"


def build_docs():
    docs_dir = os.path.join(ROOT, "docs")
    pages = []
    for name in os.listdir(docs_dir):
        if not name.endswith(".md"):
            continue
        meta, text = front_matter(open(os.path.join(docs_dir, name), encoding="utf-8").read())
        pages.append({"slug": name[:-3], "title": meta.get("title", name[:-3]), "order": float(meta.get("order", 99)),
                      "description": meta.get("description", ""), "text": text})
    pages.sort(key=lambda p: p["order"])
    os.makedirs(os.path.join(OUT, "docs"), exist_ok=True)
    for i, p in enumerate(pages):
        body, tokens = md(p["text"])
        # links between the docs written as .md (GitHub) work on the site too
        body = re.sub(r'href="([a-z\-]+)\.md(#[^"]*)?"', lambda m: f'href="{m.group(1)}.html{m.group(2) or ""}"', body)
        side = "\n".join(f'<a href="{q["slug"]}.html"{" class=\"on\"" if q is p else ""}>{html.escape(q["title"])}</a>' for q in pages)
        prev_ = pages[i - 1] if i > 0 else None
        next_ = pages[i + 1] if i + 1 < len(pages) else None
        pager = '<div class="pager">'
        if prev_:
            pager += f'<a href="{prev_["slug"]}.html"><small>Previous</small>{html.escape(prev_["title"])}</a>'
        if next_:
            pager += f'<a class="next" href="{next_["slug"]}.html"><small>Next</small>{html.escape(next_["title"])}</a>'
        pager += "</div>"
        content = f"""<div class="page-head"><div class="wrap">
	<div class="crumbs"><a href="getting-started.html">Docs</a></div>
	<h1>{html.escape(p["title"])}</h1>
	<p>{html.escape(p["description"])}</p>
</div></div>
<div class="wrap docs">
	<aside class="side"><h4>Docs</h4>
{side}
	</aside>
	<article class="prose">
{body}
{pager}
	</article>
	<aside class="toc"><h4>On this page</h4>
{toc_html(tokens)}
	</aside>
</div>"""
        out = page(p["title"], content, "../", "docs", p["description"])
        open(os.path.join(OUT, "docs", p["slug"] + ".html"), "w", encoding="utf-8").write(out)
    return pages


def parse_changelog():
    text = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
    versions = []
    for m in re.finditer(r"^## (\S+) - (.+?) - (\d{4}-\d{2}-\d{2})\n(.*?)(?=^## |\Z)", text, re.S | re.M):
        versions.append({"num": m.group(1), "title": m.group(2), "date": m.group(3), "body": m.group(4).strip()})
    return versions


def nice_date(d):
    months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    y, mo, da = d.split("-")
    return f"{int(da)} {months[int(mo) - 1]} {y}"


def build_changelog(versions):
    items = []
    for v in versions:
        body, _ = md(v["body"])
        items.append(f"""<div class="version" id="v{v["num"]}">
	<h2><span class="num">{v["num"]}</span>{html.escape(v["title"])}</h2>
	<div class="date">{nice_date(v["date"])}</div>
	<div class="prose">{body}</div>
</div>""")
    content = f"""<div class="page-head"><div class="wrap">
	<div class="crumbs">Changelog</div>
	<h1>What's new</h1>
	<p>Every development build so far, newest first. Bobba Hotel isn't released yet - these are the steps on the way.</p>
</div></div>
<div class="versions">
{chr(10).join(items)}
</div>"""
    open(os.path.join(OUT, "changelog.html"), "w", encoding="utf-8").write(
        page("Changelog", content, "", "changelog", "What's new in Bobba Hotel, build by build."))


def build_roadmap():
    text = open(os.path.join(ROOT, "ROADMAP.md"), encoding="utf-8").read()
    text = re.sub(r"^# Roadmap\n", "", text)
    body, tokens = md(text)
    content = f"""<div class="page-head"><div class="wrap">
	<div class="crumbs">Roadmap</div>
	<h1>What's coming</h1>
	<p>What's done, what's next, and the ideas agreed for later. Nothing here is a promise of when; it keeps the plans in one place.</p>
</div></div>
<div class="wrap docs" style="grid-template-columns: minmax(0, 1fr) 220px">
	<article class="prose">
{body}
	</article>
	<aside class="toc"><h4>On this page</h4>
{toc_html(tokens)}
	</aside>
</div>"""
    open(os.path.join(OUT, "roadmap.html"), "w", encoding="utf-8").write(
        page("Roadmap", content, "", "roadmap", "What's done in Bobba Hotel, what's next, and the ideas for later."))


def build_index(versions):
    tpl = open(os.path.join(SRC, "index.html"), encoding="utf-8").read()
    tpl = re.sub(r"^<!--.*?-->\n", "", tpl)
    latest = versions[0]
    # the latest build's points: their bold part, or the start of the line
    points = []
    for line in re.findall(r"^- (.+?)(?=^- |\Z)", latest["body"], re.S | re.M):
        line = " ".join(line.split())
        b = re.match(r"\*\*(.+?)\*\*:?\s*(.*)", line)
        if b:
            rest = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", b.group(2))
            rest = re.sub(r"[*`]", "", rest)
            rest = rest.split(". ")[0].split(": ")[0].split("; ")[0].rstrip(".")
            if len(rest) > 100:
                rest = rest[:100].rsplit(" ", 1)[0].rstrip(",;-( ") + "..."
            points.append(f"<li><strong>{html.escape(b.group(1))}</strong>{': ' + html.escape(rest) if rest else ''}</li>")
    body = (tpl.replace("{{VERSION}}", latest["num"]).replace("{{LATEST_TITLE}}", html.escape(latest["title"]))
            .replace("{{LATEST_DATE}}", nice_date(latest["date"])).replace("{{LATEST_LIST}}", "<ul>" + "".join(points[:5]) + "</ul>"))
    out = page("Bobba Hotel", body, "", "home",
               "A Habbo-style hotel you host yourself - in Garry's Mod or on your desktop. Rooms, furni, trading, wired and Lua scripts, all made to be modded.")
    open(os.path.join(OUT, "index.html"), "w", encoding="utf-8").write(out)


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    shutil.copytree(os.path.join(SRC, "img"), os.path.join(OUT, "img"))
    css = open(os.path.join(SRC, "style.css"), encoding="utf-8").read() + "\n/* code (pygments) */\n" + pygments_css()
    open(os.path.join(OUT, "style.css"), "w", encoding="utf-8").write(css)
    shutil.copy(os.path.join(SRC, "favicon.svg"), os.path.join(OUT, "favicon.svg"))
    open(os.path.join(OUT, "CNAME"), "w").write("playbobba.com\n")
    open(os.path.join(OUT, ".nojekyll"), "w").write("")
    versions = parse_changelog()
    pages = build_docs()
    build_changelog(versions)
    build_roadmap()
    build_index(versions)
    # 404: GitHub Pages shows it for a page that isn't there
    content = """<div class="page-head"><div class="wrap"><h1>Room not found</h1>
<p>This room doesn't exist, or its owner locked the door. <a href="/" style="color:#9db0ff">Back to the lobby</a>.</p></div></div>"""
    open(os.path.join(OUT, "404.html"), "w", encoding="utf-8").write(page("Not found", content, "/", "", "Page not found"))
    print(f"website/: index, {len(pages)} docs, changelog ({len(versions)} builds), roadmap")


if __name__ == "__main__":
    main()
