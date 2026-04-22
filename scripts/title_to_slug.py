#!/usr/bin/env python3
"""Generate URL slug from Japanese title using pykakasi romaji conversion."""

import re
import sys
from pykakasi import kakasi

# Initialize kakasi (Hepburn romanization)
k = kakasi()
k.setMode('H', 'a')  # Hiragana → romaji
k.setMode('K', 'a')  # Katakana → romaji
k.setMode('J', 'a')  # Kanji → romaji
conv = k.convert

def title_to_slug(title: str) -> str:
    """Convert Japanese title to URL-safe slug."""
    # Strip leading number prefix like "123: " or "123: "
    title = re.sub(r'^\d+\s*[:：]\s*', '', title)
    
    # Convert to romaji
    result = conv(title)
    romaji = '-'.join([r['hepburn'] for r in result])
    
    # Clean: lowercase, replace non-alphanumeric with hyphens, collapse
    slug = re.sub(r'[^a-z0-9]+', '-', romaji.lower()).strip('-')
    slug = re.sub(r'-+', '-', slug)
    
    # Truncate if too long (keep it readable)
    if len(slug) > 100:
        slug = slug[:100].rstrip('-')
    
    # Fallback for empty slugs
    if not slug:
        import hashlib
        slug = hashlib.sha256(title.encode()).hexdigest()[:12]
    
    return slug

if __name__ == '__main__':
    title = sys.argv[1]
    print(title_to_slug(title))