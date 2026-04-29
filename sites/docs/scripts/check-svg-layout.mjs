import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { spawn } from 'node:child_process'

const targets = process.argv.slice(2)

if (!targets.length) {
  console.error('usage: node scripts/check-svg-layout.mjs <svg-url-or-path> [...]')
  process.exit(2)
}

const chrome =
  process.env.CHROME_BIN ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
const port = 9400 + (process.pid % 400)
const userDataDir = await mkdtemp(join(tmpdir(), 'platform-docs-svg-check-'))

const child = spawn(chrome, [
  '--headless=new',
  '--disable-gpu',
  '--hide-scrollbars',
  `--user-data-dir=${userDataDir}`,
  `--remote-debugging-port=${port}`,
  '--window-size=1400,900',
  'about:blank',
], {
  stdio: 'ignore',
})

async function waitForDevtools() {
  const url = `http://127.0.0.1:${port}/json/version`
  for (let index = 0; index < 80; index += 1) {
    try {
      const response = await fetch(url)
      if (response.ok) return
    } catch {
      // Chrome is still starting.
    }
    await new Promise(resolve => setTimeout(resolve, 100))
  }
  throw new Error('Timed out waiting for Chrome DevTools')
}

function toUrl(value) {
  if (/^https?:\/\//.test(value)) return value
  return `file://${resolve(value)}`
}

async function openTab(url) {
  return fetch(`http://127.0.0.1:${port}/json/new`, {
    method: 'PUT',
    body: url,
  }).then(response => response.json())
}

async function inspect(url) {
  const tab = await openTab(url)
  const ws = new WebSocket(tab.webSocketDebuggerUrl)
  let id = 1
  const pending = new Map()

  ws.onmessage = message => {
    const data = JSON.parse(message.data)
    if (data.id && pending.has(data.id)) {
      pending.get(data.id)(data)
      pending.delete(data.id)
    }
  }

  await new Promise(resolve => {
    ws.onopen = resolve
  })

  const send = (method, params = {}) =>
    new Promise(resolve => {
      const messageId = id
      id += 1
      pending.set(messageId, resolve)
      ws.send(JSON.stringify({ id: messageId, method, params }))
    })

  await send('Page.enable')
  await send('Runtime.enable')
  await send('Page.navigate', { url })
  await new Promise(resolve => setTimeout(resolve, 800))

  const expression = `(() => {
    const svg = document.querySelector('svg')
    if (!svg) return { error: 'No SVG element found' }
    const viewBox = svg.viewBox.baseVal
    const rects = Array.from(svg.querySelectorAll('rect')).map((el, index) => {
      const b = el.getBBox()
      return {
        index,
        x: b.x,
        y: b.y,
        width: b.width,
        height: b.height,
        right: b.x + b.width,
        bottom: b.y + b.height,
        opacity: el.getAttribute('opacity') || '',
      }
    }).filter(r => r.width > 80 && r.height > 28 && r.opacity !== '0.22')

    function ownerRectForText(el) {
      if (svg.getAttribute('data-d2-version')) {
        let current = el.parentElement
        while (current && current !== svg) {
          const rect = current.querySelector(':scope > g.shape rect, :scope > .shape rect')
          if (rect) return rect
          current = current.parentElement
        }
        return null
      }

      return null
    }

    const texts = Array.from(svg.querySelectorAll('text')).map((el, index) => {
      const b = el.getBBox()
      const cx = b.x + b.width / 2
      const cy = b.y + b.height / 2
      const owner = ownerRectForText(el)
      let rect = null
      if (owner) {
        const ownerBox = owner.getBBox()
        rect = {
          index: rects.find(r => Math.abs(r.x - ownerBox.x) < 0.1 && Math.abs(r.y - ownerBox.y) < 0.1)?.index ?? -1,
          x: ownerBox.x,
          y: ownerBox.y,
          width: ownerBox.width,
          height: ownerBox.height,
          right: ownerBox.x + ownerBox.width,
          bottom: ownerBox.y + ownerBox.height,
        }
      } else {
        const containers = rects
          .filter(r => cx >= r.x && cx <= r.right && cy >= r.y && cy <= r.bottom)
          .sort((a, b) => (a.width * a.height) - (b.width * b.height))
        rect = containers[0]
      }
      const pad = rect ? {
        left: b.x - rect.x,
        right: rect.right - (b.x + b.width),
        top: b.y - rect.y,
        bottom: rect.bottom - (b.y + b.height),
        rect: rect.index,
      } : null
      return {
        index,
        text: el.textContent,
        hasOwner: Boolean(owner),
        isContainerLabel: Boolean(owner && el.parentElement?.querySelectorAll('g.shape rect, .shape rect').length > 1),
        x: b.x,
        y: b.y,
        width: b.width,
        right: b.x + b.width,
        pad,
      }
    })

    const issues = texts.filter(t =>
      (svg.getAttribute('data-d2-version') && !t.pad && t.text.trim()) ||
      (t.pad && (
        t.pad.left < 16 ||
        t.pad.right < 16 ||
        t.pad.top < (svg.getAttribute('data-d2-version') ? 4 : 8) ||
        t.pad.bottom < 12
      ))
    ).map(t => ({
      text: t.text,
      bbox: {
        x: Math.round(t.x * 10) / 10,
        y: Math.round(t.y * 10) / 10,
        width: Math.round(t.width * 10) / 10,
        right: Math.round(t.right * 10) / 10,
      },
      padding: t.pad ? Object.fromEntries(Object.entries(t.pad).map(([key, value]) => [
          key,
          typeof value === 'number' ? Math.round(value * 10) / 10 : value,
        ])) : null,
    }))

    return {
      viewBox: { width: viewBox.width, height: viewBox.height },
      checkedText: texts.filter(t => t.pad).length,
      issueCount: issues.length,
      issues,
    }
  })()`

  const result = await send('Runtime.evaluate', {
    expression,
    returnByValue: true,
  })

  ws.close()
  await fetch(`http://127.0.0.1:${port}/json/close/${tab.id}`)
  return result.result.result.value
}

try {
  await waitForDevtools()
  const reports = []
  for (const target of targets) {
    const report = await inspect(toUrl(target))
    reports.push({ target, ...report })
    if (report.issueCount > 0 || report.error) process.exitCode = 1
  }
  console.log(JSON.stringify(targets.length === 1 ? reports[0] : reports, null, 2))
} finally {
  child.kill('SIGTERM')
  await new Promise(resolve => {
    child.once('exit', resolve)
    setTimeout(resolve, 750)
  })
  await rm(userDataDir, {
    recursive: true,
    force: true,
    maxRetries: 5,
    retryDelay: 100,
  })
}
