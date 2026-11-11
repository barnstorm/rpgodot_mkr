#!/bin/bash
# Copies docs/wiki/ into the repository's GitHub wiki and pushes it.
# Usage: tools/publish_wiki.sh [owner/repo]        (default: barnstorm/rpgodot_mkr)
#
# GitHub wikis need the wiki turned on in the repository's settings, and (for private repositories)
# a paid plan. The wiki's git repository only exists after its first page has been created on the
# web: open the repository's Wiki tab and save any page once, then run this script.
#
# Links between pages are written as `Page.md` so they work when browsing docs/wiki on GitHub;
# the wiki wants `Page`, so the copies have the `.md` removed from relative page links.
set -e
REPO="${1:-barnstorm/rpgodot_mkr}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
git clone --quiet "https://github.com/$REPO.wiki.git" "$WORK/wiki"
cp "$ROOT"/docs/wiki/*.md "$WORK/wiki/"
mkdir -p "$WORK/wiki/images"
cp "$ROOT"/docs/wiki/images/*.png "$WORK/wiki/images/"
# ](Page.md) and ](Page.md#anchor)  ->  ](Page) and ](Page#anchor), for relative links only.
sed -i -E 's/\]\(([A-Za-z0-9_-]+)\.md(#[^)]*)?\)/](\1\2)/g' "$WORK"/wiki/*.md
cd "$WORK/wiki"
git add -A
if git diff --cached --quiet; then
	echo "Wiki already up to date."
else
	git commit --quiet -m "Update wiki from docs/wiki"
	git push --quiet
	echo "Wiki updated: https://github.com/$REPO/wiki"
fi
