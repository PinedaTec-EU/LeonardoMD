#!/usr/bin/env python3
"""Check real pointer activation against the served, bundled calendar fixture."""
import argparse
import os
import subprocess
import tempfile

CHECK = r'''async page => {
  const state = () => page.evaluate(() => ({
    hidden: document.querySelector('.leonardo-calendar').hidden,
    title: document.querySelector('.leonardo-calendar-header').textContent,
    values: [...document.querySelectorAll('input')].map(input => input.value),
    snapshot: LeonardoForms.snapshot()
  }));
  await page.getByRole('button', {name: 'Mes siguiente'}).first().click();
  let result = await state();
  if (result.hidden || !result.title.includes('noviembre')) throw new Error('Pointer next month failed');
  await page.getByRole('button', {name: 'Mes anterior'}).first().click();
  result = await state();
  if (result.hidden || !result.title.includes('octubre')) throw new Error('Pointer previous month failed');
  await page.locator('[data-date="2026-10-18"]').first().click();
  result = await state();
  if (!result.hidden || !result.values.every(value => value === '2026-10-18') || result.snapshot.changes.review !== '2026-10-18') throw new Error('Pointer date selection/synchronization failed');
  await page.getByRole('button', {name: 'Abrir calendario'}).first().click();
  if ((await state()).hidden) throw new Error('Pointer reopen failed');
  await page.locator('input').nth(1).click();
  if (!(await state()).hidden) throw new Error('Outside pointer dismissal failed');
  await page.getByRole('button', {name: 'Abrir calendario'}).first().click();
  await page.keyboard.press('ArrowRight');
  const focused = await page.evaluate(() => document.activeElement.dataset.date);
  if (focused !== '2026-10-19') throw new Error('Keyboard navigation after pointer selection failed');
  await page.keyboard.press('Escape');
  if (!(await state()).hidden) throw new Error('Escape dismissal failed');
  return {next: true, previous: true, selection: true, duplicates: true, reopen: true, outside: true, keyboard: true};
}'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cli', default='playwright-cli')
    parser.add_argument('--browser', choices=['webkit', 'msedge'], default='webkit')
    parser.add_argument('--url', default='http://127.0.0.1:8933/doc/validation/form-calendar/preview.html')
    args = parser.parse_args()
    session = f'calendar-pointer-{os.getpid()}'
    with tempfile.TemporaryDirectory(prefix='leonardo-calendar-pointer-') as scratch:
        def run(*command):
            result = subprocess.run([args.cli, f'-s={session}', *command], cwd=scratch,
                                    text=True, capture_output=True)
            if result.returncode:
                raise RuntimeError(result.stdout + result.stderr)
            return result.stdout

        try:
            run('open', args.url, '--browser', args.browser)
            print(run('run-code', CHECK).split('### Ran Playwright code')[0].strip())
        finally:
            run('close')



if __name__ == '__main__':
    main()
