// Headless Playwright driver (VERIFY_BROWSER=chromium|firefox|webkit, default chromium) for the compose dev platform started by control.sh.
// Usage (via control.sh):
//   control.sh drive login                 open subnetcalc dev, complete Dex SSO, capture the app
//   control.sh drive lookup <address>      login, then submit #lookup-form and capture #results
// Uses playwright-core from tests/kubernetes/sso (installed by control.sh launch) and its own browser builds.
// Writes NN-<step>.png, NN-<step>.txt (visible text of #results or the page) and steps.jsonl.
import { appendFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join } from 'node:path'

const root = process.env.VERIFY_REPO_ROOT
const require = createRequire(join(root, 'tests/kubernetes/sso/package.json'))
const playwright = require('playwright-core')
const browserName = process.env.VERIFY_BROWSER || 'chromium'
if (!['chromium', 'firefox', 'webkit'].includes(browserName)) {
  throw new Error(`unknown VERIFY_BROWSER ${browserName}; use chromium, firefox or webkit`)
}

const appUrl = process.env.VERIFY_APP_URL
const out = process.env.VERIFY_EVIDENCE_DIR
const login = process.env.VERIFY_DEX_LOGIN || 'demo@dev.test'
const password = process.env.VERIFY_DEX_PASSWORD || 'password123'
mkdirSync(out, { recursive: true })

let step = 0
const log = (record) => {
  const line = JSON.stringify({ at: new Date().toISOString(), ...record })
  console.log(line)
  appendFileSync(join(out, 'steps.jsonl'), `${line}\n`)
}

const browser = await playwright[browserName].launch({ headless: true })
const page = await browser.newPage({ viewport: { width: 1280, height: 1000 } })
const consoleErrors = []
page.on('pageerror', (e) => consoleErrors.push(String(e)))
page.on('console', (m) => m.type() === 'error' && consoleErrors.push(m.text()))

const capture = async (name, selector = 'body') => {
  step += 1
  const prefix = join(out, `${String(step).padStart(2, '0')}-${name}`)
  await page.screenshot({ path: `${prefix}.png` })
  const text = await page
    .locator(selector)
    .innerText({ timeout: 2000 })
    .catch(() => '')
  writeFileSync(`${prefix}.txt`, text)
  log({ step: name, url: page.url(), host: new URL(page.url()).host })
}

const signIn = async () => {
  await page.goto(appUrl)
  await page.waitForSelector('#login', { timeout: 60_000 })
  await capture('dex-login-form')
  await page.fill('#login', login)
  await page.fill('#password', password)
  await page.click('#submit-login')
  const grant = page.locator('button[type="submit"]:has-text("Grant Access")')
  if (await grant.isVisible({ timeout: 3000 }).catch(() => false)) await grant.click()
  await page.waitForURL((url) => url.origin === new URL(appUrl).origin, { timeout: 60_000 })
  await page.waitForSelector('#lookup-form')
  await page.waitForFunction(() => !/Checking API/.test(document.querySelector('#api-status')?.textContent || ''))
  await capture('app-signed-in')
  log({
    authState: await page.locator('#auth-state').innerText(),
    apiStatus: await page.locator('#api-status').innerText(),
  })
}

const [cmd, ...args] = process.argv.slice(2)
let failed = false
try {
  log({ command: cmd, args, appUrl, login, browser: browserName, browserVersion: browser.version() })
  await signIn()
  if (cmd === 'lookup') {
    const address = args[0]
    if (!address) throw new Error('lookup needs an address, e.g. 10.0.0.0/24')
    await page.fill('#ip-address', address)
    await page.click('#lookup-btn')
    await page.waitForSelector('#results:not([hidden])', { timeout: 30_000 })
    await page.waitForFunction(
      () => {
        const text = document.querySelector('#results-content')?.textContent?.trim() || ''
        return text.length > 0 && !/^Loading/.test(text)
      },
      undefined,
      { timeout: 30_000 }
    )
    await capture('lookup-results', '#results')
  } else if (cmd !== 'login') {
    throw new Error(`unknown command ${cmd}; use login | lookup <address>`)
  }
} catch (error) {
  failed = true
  await capture('failure').catch(() => {})
  log({ result: 'FAIL', error: String(error) })
} finally {
  log({ consoleErrors })
  if (!failed) log({ result: 'PASS', command: cmd })
  await browser.close()
}
process.exit(failed ? 1 : 0)
