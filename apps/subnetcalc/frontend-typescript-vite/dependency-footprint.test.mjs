import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const appDir = new URL('.', import.meta.url)
const packageJson = JSON.parse(fs.readFileSync(new URL('./package.json', appDir), 'utf8'))

test('typescript-vite runtime dependencies stay slim', () => {
  const dependencies = packageJson.dependencies ?? {}
  assert.equal(dependencies['@picocss/pico'], undefined)
  assert.equal(dependencies['@subnetcalc/shared-frontend'], undefined)
})

test('typescript-vite build stays self-contained', () => {
  const buildScripts = [packageJson.scripts?.build, packageJson.scripts?.['type-check'], packageJson.scripts?.check]
    .filter(Boolean)
    .join('\n')

  assert.equal(buildScripts.includes('../shared-frontend'), false)
})

test('typescript-vite html does not rely on external Pico CDN stylesheets', () => {
  for (const relativePath of ['index.html', path.join('public', 'logged-out.html')]) {
    const content = fs.readFileSync(new URL(relativePath, appDir), 'utf8')
    assert.equal(content.includes('cdn.jsdelivr.net'), false, relativePath)
    assert.equal(content.toLowerCase().includes('picocss'), false, relativePath)
  }
})
