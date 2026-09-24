#!/usr/bin/env python3
"""Test the offline design preview, NOT the native macOS UI.
Optional dependency: Playwright for Python and a Chromium installation.
CHROMIUM_PATH can select an existing system binary. No network or Git writes.
"""
import json
import os
from pathlib import Path
import shutil
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = Path(os.environ.get('PREVIEW_OUTPUT', ROOT / 'dist' / 'preview'))
OUTPUT.mkdir(parents=True, exist_ok=True)

with sync_playwright() as p:
    binary = os.environ.get('CHROMIUM_PATH') or shutil.which('chromium')
    options = {'headless': True}
    if binary:
        options['executable_path'] = binary
    browser = p.chromium.launch(**options)
    page = browser.new_page(viewport={'width': 1440, 'height': 1240}, device_scale_factor=1)
    page.set_default_timeout(5000)
    errors = []
    page.on('pageerror', lambda error: errors.append(str(error)))
    # Inline source avoids any file URL or server requirement. All assets are inlined.
    page.set_content((ROOT / 'docs' / 'preview.html').read_text(), wait_until='load')
    assert page.locator('.card').count() == 3
    assert page.locator('.wt').count() == 9
    assert page.evaluate('document.documentElement.scrollWidth') == 1440
    page.screenshot(path=str(OUTPUT / 'preview-light.png'), full_page=True)
    page.locator('#search').fill('benchmark')
    assert page.locator('.card').count() == 1
    assert 'Research' in page.locator('.card').inner_text()
    page.locator('#search').fill('no-such-demo-repository')
    assert page.locator('.card').count() == 0
    page.locator('#search').fill('')
    page.locator('.wt').first.click()
    assert page.locator('#inspector').is_visible()
    assert page.locator('#wtpath').inner_text().startswith('/demo/')
    page.locator('#close').click()
    assert not page.locator('#inspector').is_visible()
    page.locator('.nav[data-repo="Research"]').click()
    assert page.locator('.card').count() == 1
    page.locator('.nav[data-repo="all"]').click()
    assert page.locator('.card').count() == 3
    page.locator('#filter').click()
    assert page.locator('.card').count() < 3
    page.locator('#filter').click()
    assert page.locator('.card').count() == 3
    page.locator('#theme').click()
    assert 'dark' in page.locator('body').get_attribute('class')
    page.screenshot(path=str(OUTPUT / 'preview-dark.png'), full_page=True)
    page.locator('#add').click()
    assert page.locator('#toast').is_visible()
    page.set_viewport_size({'width': 980, 'height': 900})
    assert page.evaluate('document.documentElement.scrollWidth') == 980
    page.screenshot(path=str(OUTPUT / 'preview-narrow.png'), full_page=True)
    assert not errors, errors
    result = {'status': 'pass', 'scope': 'Offline HTML design preview ONLY; not native SwiftUI',
        'checks': ['3 repository cards', '9 worktree markers', 'search match', 'search empty state',
                   'inspector open/close', 'repository focus/back', 'attention filter', 'light/dark',
                   'non-mutating placeholder action', '1440px and 980px no horizontal overflow',
                   'no JavaScript page errors'],
        'browser': browser.version, 'pageErrors': errors}
    (OUTPUT / 'preview-checks.json').write_text(json.dumps(result, indent=2, ensure_ascii=False))
    print(json.dumps(result, indent=2, ensure_ascii=False))
    browser.close()
