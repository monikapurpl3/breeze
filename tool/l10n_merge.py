#!/usr/bin/env python3
"""Build lib/l10n/app_<lang>.arb from lib/l10n/parts/<group>_<lang>.arb.

    python3 tool/l10n_merge.py          # merge and check
    python3 tool/l10n_merge.py --check  # check only, write nothing

The messages are kept in one file per screen group and language, so that
groups can be translated side by side without editing the same file; gen-l10n
wants one file per language, which this assembles. Run it after editing any
part; `flutter gen-l10n` (or any build) then regenerates the Dart.

It refuses, rather than writing something gen-l10n would half-accept, when:
  * a key is defined by two groups;
  * a language lacks a key English has, or has one English lacks;
  * a message's {placeholders} differ from English's -- a translation that
    drops {name} would compile and quietly lose the unit's name;
  * an English message with a plural or select has a translation without one.
"""
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PARTS = os.path.join(ROOT, 'lib', 'l10n', 'parts')
OUT = os.path.join(ROOT, 'lib', 'l10n')
TEMPLATE = 'en'
LANGS = ['en', 'hr', 'sr', 'sl', 'fr', 'it', 'zh']


def load_parts():
    """{lang: [(group, {key: value})]} in group order, common first."""
    found = {}
    for name in sorted(os.listdir(PARTS)):
        m = re.fullmatch(r'([a-z0-9]+)_([a-z]{2})\.arb', name)
        if not m:
            sys.exit(f'l10n_merge: unexpected file in parts: {name}')
        group, lang = m.groups()
        with io.open(os.path.join(PARTS, name), encoding='utf-8') as f:
            try:
                data = json.load(f)
            except json.JSONDecodeError as e:
                sys.exit(f'l10n_merge: {name} is not valid JSON: {e}')
        data.pop('@@locale', None)
        found.setdefault(lang, []).append((group, data))
    for lang in found:
        found[lang].sort(key=lambda gd: (gd[0] != 'common', gd[0]))
    return found


def placeholders(message):
    """The {names} a message substitutes, ignoring ICU plural/select bodies."""
    names = set()
    depth = 0
    i = 0
    while i < len(message):
        c = message[i]
        if c == '{':
            j = i + 1
            while j < len(message) and (message[j].isalnum() or message[j] == '_'):
                j += 1
            if depth == 0 or (j < len(message) and message[j] in ',}'):
                word = message[i + 1:j]
                if word and j < len(message) and message[j] in ',}':
                    names.add(word)
            depth += 1
        elif c == '}':
            depth -= 1
        i += 1
    return names


def icu_kind(message):
    m = re.search(r'\{\s*\w+\s*,\s*(plural|select)\s*,', message)
    return m.group(1) if m else None


def main():
    check_only = '--check' in sys.argv
    parts = load_parts()
    problems = []
    merged = {}
    for lang in LANGS:
        if lang not in parts:
            problems.append(f'no parts at all for {lang}')
            continue
        out = {'@@locale': lang}
        owner = {}
        for group, data in parts[lang]:
            for key, value in data.items():
                if key in owner:
                    problems.append(f'{lang}: {key} is defined by both {owner[key]} and {group}')
                    continue
                owner[key] = group
                out[key] = value
        merged[lang] = out

    en = merged.get(TEMPLATE, {})
    en_keys = {k for k in en if not k.startswith('@')}
    for lang in LANGS:
        if lang == TEMPLATE or lang not in merged:
            continue
        keys = {k for k in merged[lang] if not k.startswith('@')}
        for k in sorted(en_keys - keys):
            problems.append(f'{lang}: missing {k}')
        for k in sorted(keys - en_keys):
            problems.append(f'{lang}: {k} is not in English')
        for k in sorted(en_keys & keys):
            want, got = placeholders(en[k]), placeholders(merged[lang][k])
            if want != got:
                problems.append(f'{lang}: {k} has {sorted(got)}, English has {sorted(want)}')
            kind = icu_kind(en[k])
            if kind and icu_kind(merged[lang][k]) != kind:
                problems.append(f'{lang}: {k} lacks the {kind} English has')
        # Descriptions live in English only.
        merged[lang] = {k: v for k, v in merged[lang].items()
                        if not (k.startswith('@') and k != '@@locale')}

    if problems:
        for p in problems:
            print('  ' + p)
        sys.exit(f'l10n_merge: {len(problems)} problem(s); nothing written')
    if check_only:
        print(f'l10n_merge: {len(en_keys)} messages in {len(LANGS)} languages, consistent')
        return
    for lang, data in merged.items():
        path = os.path.join(OUT, f'app_{lang}.arb')
        with io.open(path, 'w', encoding='utf-8', newline='\n') as f:
            f.write(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print(f'l10n_merge: {len(en_keys)} messages in {len(LANGS)} languages written')


if __name__ == '__main__':
    main()
