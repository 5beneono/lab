#!/usr/bin/env python3
"""Batch generate URL slugs from Japanese titles using pykakasi.
Reads titles from stdin (one per line), outputs slug for each.
Much faster than invoking Python per-file."""

import re
import sys
import hashlib
from pykakasi import kakasi

# Initialize kakasi once
k = kakasi()
k.setMode('H', 'a')
k.setMode('K', 'a')
k.setMode('J', 'a')
conv = k.convert

def title_to_slug(title: str) -> str:
    title = re.sub(r'^\d+\s*[:：]\s*', '', title)
    result = conv(title)
    romaji = '-'.join([r['hepburn'] for r in result])
    slug = re.sub(r'[^a-z0-9]+', '-', romaji.lower()).strip('-')
    slug = re.sub(r'-+', '-', slug)
    if len(slug) > 100:
        slug = slug[:100].rstrip('-')
    if not slug:
        slug = hashlib.sha256(title.encode()).hexdigest()[:12]
    return slug

used_slugs = {}

for line in sys.stdin:
    line = line.rstrip('\n')
    slug = title_to_slug(line)
    # Handle collisions
    if slug in used_slugs:
        used_slugs[slug] += 1
        slug = f"{slug}-{used_slugs[slug]}"
    else:
        used_slugs[slug] = 1
    print(slug)