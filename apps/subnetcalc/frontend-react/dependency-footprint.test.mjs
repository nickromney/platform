import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'

const appDir = new URL('.', import.meta.url)
const packageJson = JSON.parse(fs.readFileSync(new URL('./package.json', appDir), 'utf8'))

test('react runtime dependencies stay slim', () => {
  const dependencies = packageJson.dependencies ?? {}
  assert.equal(dependencies.express, undefined)
  assert.equal(dependencies['@azure/identity'], undefined)
  assert.equal(dependencies['@subnetcalc/shared-frontend'], undefined)
})

test('react docker build no longer installs shared-frontend as a package', () => {
  for (const relativePath of ['Dockerfile', 'Dockerfile.server']) {
    const content = fs.readFileSync(new URL(relativePath, appDir), 'utf8')
    assert.equal(content.includes('COPY ./shared-frontend/package.json'), false, relativePath)
    assert.equal(content.includes('WORKDIR /shared-frontend'), false, relativePath)
  }
})

test('react html does not rely on external Pico CDN stylesheets', () => {
  for (const relativePath of ['index.html', path.join('public', 'logged-out.html')]) {
    const content = fs.readFileSync(new URL(relativePath, appDir), 'utf8')
    assert.equal(content.includes('cdn.jsdelivr.net'), false, relativePath)
    assert.equal(content.toLowerCase().includes('picocss'), false, relativePath)
  }
})
