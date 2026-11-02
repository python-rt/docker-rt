#!/usr/bin/env python3
"""Checks for new RT releases and updates the RT versions of this project.

  rt-release.py check [--listing FILE]   prints the available updates as JSON:
                                         {"updates": [{"old": "6.0.4", "new": "6.0.5"}], "new_series": ["6.1.0"]}
  rt-release.py apply OLD NEW            updates the version OLD to NEW in versions.json, the Dockerfile and README.md

"updates" are newer releases of the series (major.minor) in versions.json, "new_series" is the newest release if it
belongs to a newer series than all in versions.json. Branches (e.g. "stable") in versions.json are not checked. A
release counts only when both the tarball and its signature are listed, i.e. when it is completely uploaded.
"""

import argparse
import json
import pathlib
import re
import sys
import urllib.request
from typing import Any

LISTING_URL = 'https://download.bestpractical.com/pub/rt/release/'
ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSIONS_FILE = ROOT / 'versions.json'
VERSION_RE = re.compile(r'^(\d+)\.(\d+)\.(\d+)$')

Version = tuple[int, int, int]


def parse_version(text: str) -> Version | None:
    match = VERSION_RE.match(text)
    if not match:
        return None
    major, minor, patch = (int(part) for part in match.groups())
    return major, minor, patch


def format_version(version: Version) -> str:
    return '.'.join(str(part) for part in version)


def released_versions(listing: str) -> list[Version]:
    files = set(re.findall(r'href="(rt-[^"/]+)"', listing))
    versions = []
    for name in files:
        match = re.fullmatch(r'rt-(\d+\.\d+\.\d+)\.tar\.gz', name)
        if match and f'{name}.asc' in files:
            version = parse_version(match.group(1))
            if version:
                versions.append(version)
    return sorted(versions)


def load_versions() -> list[dict[str, str]]:
    versions: list[dict[str, str]] = json.loads(VERSIONS_FILE.read_text())
    return versions


def check(listing: str) -> dict[str, list[Any]]:
    released = released_versions(listing)
    if not released:
        sys.exit('no releases found in the listing')

    configured = [version for entry in load_versions() if (version := parse_version(entry['rt']))]
    updates = []
    for current in configured:
        same_series = [version for version in released if version[:2] == current[:2]]
        if same_series and same_series[-1] > current:
            updates.append({'old': format_version(current), 'new': format_version(same_series[-1])})

    new_series = []
    newest = released[-1]
    if configured and newest[:2] not in {version[:2] for version in configured} and newest > max(configured):
        new_series.append(format_version(newest))

    return {'updates': updates, 'new_series': new_series}


def apply(old: str, new: str) -> None:
    if not parse_version(old) or not parse_version(new):
        sys.exit(f'invalid version: {old} or {new}')

    versions = load_versions()
    found = False
    for entry in versions:
        if entry['rt'] == old:
            found = True
            entry['rt'] = new
            entry['tags'] = ' '.join(new if tag == old else tag for tag in entry['tags'].split())
    if not found:
        sys.exit(f'{old} not found in {VERSIONS_FILE.name}')
    VERSIONS_FILE.write_text('[\n' + ',\n'.join(f'  {json.dumps(entry)}' for entry in versions) + '\n]\n')

    # the default of the Dockerfile only follows the version it has, e.g. not when an older series is updated
    dockerfile = ROOT / 'Dockerfile'
    dockerfile.write_text(dockerfile.read_text().replace(f'ARG RT_VERSION={old}\n', f'ARG RT_VERSION={new}\n'))
    # with version boundaries, so e.g. 6.0.1 does not match in 6.0.10
    readme = ROOT / 'README.md'
    readme.write_text(re.sub(rf'(?<![\d.]){re.escape(old)}(?![\d])', new, readme.read_text()))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    check_parser = commands.add_parser('check')
    check_parser.add_argument('--listing', type=pathlib.Path, help='release listing file instead of downloading it')
    apply_parser = commands.add_parser('apply')
    apply_parser.add_argument('old')
    apply_parser.add_argument('new')
    args = parser.parse_args()

    if args.command == 'check':
        if args.listing:
            listing = args.listing.read_text()
        else:
            request = urllib.request.Request(LISTING_URL, headers={'User-Agent': 'python-rt/docker-rt release check'})
            with urllib.request.urlopen(request, timeout=60) as response:
                listing = response.read().decode()
        print(json.dumps(check(listing)))
    else:
        apply(args.old, args.new)


if __name__ == '__main__':
    main()
