import { execFileSync } from 'node:child_process'
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

const repo = process.cwd()

const focusedSvgLayoutTargets = [
  'public/diagrams/generated/apps-patterns-1-light.svg',
  'public/diagrams/generated/apps-patterns-1-dark.svg',
  'public/diagrams/generated/concepts-stage-ladder-1-light.svg',
  'public/diagrams/generated/concepts-stage-ladder-1-dark.svg',
  'public/diagrams/generated/concepts-iac-boundaries-1-light.svg',
  'public/diagrams/generated/concepts-iac-boundaries-1-dark.svg',
  'public/diagrams/generated/concepts-manifest-assembly-1-light.svg',
  'public/diagrams/generated/concepts-manifest-assembly-1-dark.svg',
  'public/diagrams/manifest-assembly.svg',
  'public/diagrams/manifest-assembly-dark.svg',
  'public/diagrams/generated/index-1-light.svg',
  'public/diagrams/generated/index-1-dark.svg',
  'public/diagrams/idp-local-workbench.svg',
  'public/diagrams/idp-local-workbench-dark.svg',
  'public/diagrams/mental-model-core.svg',
  'public/diagrams/mental-model-core-dark.svg',
]

const arrowRules = [
  {
    file: 'public/diagrams/generated/apps-patterns-1-light.svg',
    allow: /^M[\d.]+ [\d.]+ H[\d.]+$/,
    direction: 'down',
  },
  {
    file: 'public/diagrams/generated/apps-patterns-1-dark.svg',
    allow: /^M[\d.]+ [\d.]+ H[\d.]+$/,
    direction: 'down',
  },
  {
    file: 'public/diagrams/generated/concepts-iac-boundaries-1-light.svg',
    direction: 'right',
  },
  {
    file: 'public/diagrams/generated/concepts-iac-boundaries-1-dark.svg',
    direction: 'right',
  },
  {
    file: 'public/diagrams/generated/concepts-manifest-assembly-1-light.svg',
    direction: 'down',
  },
  {
    file: 'public/diagrams/generated/concepts-manifest-assembly-1-dark.svg',
    direction: 'down',
  },
  {
    file: 'public/diagrams/manifest-assembly.svg',
    direction: 'right',
  },
  {
    file: 'public/diagrams/manifest-assembly-dark.svg',
    direction: 'right',
  },
  {
    file: 'public/diagrams/generated/concepts-stage-ladder-1-light.svg',
    allow: /^M[\d.]+ [\d.]+ V[\d.]+$/,
    direction: 'down',
  },
  {
    file: 'public/diagrams/generated/concepts-stage-ladder-1-dark.svg',
    allow: /^M[\d.]+ [\d.]+ V[\d.]+$/,
    direction: 'down',
  },
]

function walk(dir, files = []) {
  for (const entry of readdirSync(join(repo, dir), { withFileTypes: true })) {
    const path = `${dir}/${entry.name}`
    if (entry.isDirectory()) walk(path, files)
    else files.push(path)
  }
  return files
}

function d2Outputs() {
  const outputs = new Map()
  for (const file of walk('diagrams/d2').filter(path => path.endsWith('.d2'))) {
    const source = readFileSync(join(repo, file), 'utf8')
    const light = source.match(/^#\s*@light\s+(.+)$/m)?.[1]?.trim()
    const dark = source.match(/^#\s*@dark\s+(.+)$/m)?.[1]?.trim()
    if (light) outputs.set(light, { theme: 'light', source: file })
    if (dark) outputs.set(dark, { theme: 'dark', source: file })
  }
  return outputs
}

const d2OutputMap = d2Outputs()
const themePairs = [...d2OutputMap.entries()].map(([file, { theme }]) => [file, theme])
const svgLayoutTargets = focusedSvgLayoutTargets

function run(name, fn) {
  try {
    fn()
    console.log(`ok ${name}`)
  } catch (error) {
    console.error(`not ok ${name}`)
    if (error.stdout) process.stderr.write(error.stdout)
    if (error.stderr) process.stderr.write(error.stderr)
    else console.error(error.message)
    process.exitCode = 1
  }
}

function checkSvgLayout(files) {
  execFileSync('node', ['scripts/check-svg-layout.mjs', ...files], {
    cwd: repo,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })
}

function pathDataForLines(svg) {
  const out = []
  const pathPattern = /<path\b([^>]*\bclass="[^"]*\bline\b[^"]*"[^>]*)>/g
  for (const match of svg.matchAll(pathPattern)) {
    const d = match[1].match(/\bd="([^"]+)"/)?.[1]
    if (d) out.push(d.trim())
  }
  return out
}

function d2ConnectionPaths(svg) {
  const out = []
  const pathPattern = /<path\b([^>]*\bclass="[^"]*\bconnection\b[^"]*"[^>]*)>/g
  for (const match of svg.matchAll(pathPattern)) {
    const d = match[1].match(/\bd="([^"]+)"/)?.[1]
    if (d) out.push(d.trim())
  }
  return out
}

function parsePolyline(path) {
  const points = [...path.matchAll(/(?:M|L)\s*([\d.]+)\s+([\d.]+)/g)].map(match => ({
    x: Number(match[1]),
    y: Number(match[2]),
  }))
  return points.length >= 2 ? points : null
}

function isDownwardVertical(path) {
  const points = parsePolyline(path)
  if (!points) return false
  const first = points[0]
  const last = points[points.length - 1]
  const sameColumn = points.every(point => Math.abs(point.x - first.x) < 0.01)
  return sameColumn && last.y > first.y
}

function isRightward(path) {
  const points = parsePolyline(path)
  if (!points) return false
  const first = points[0]
  const last = points[points.length - 1]
  const movesBackward = points.slice(1).some((point, index) => point.x < points[index].x - 0.01)
  return !movesBackward && last.x > first.x
}

function yDirection(path) {
  const match = path.match(/^M[\d.]+ ([\d.]+) V([\d.]+)$/)
  if (!match) return null
  return Number(match[2]) - Number(match[1])
}

run('svg layout all D2 diagrams', () => checkSvgLayout(svgLayoutTargets))

for (const rule of arrowRules) {
  run(`arrow discipline ${rule.file}`, () => {
    const svg = readFileSync(join(repo, rule.file), 'utf8')
    if (svg.includes('data-d2-version=')) {
      const paths = d2ConnectionPaths(svg)
      if (!paths.length) throw new Error('Expected D2 connection paths')
      const bad = paths.filter(path => {
        if (rule.direction === 'down') return !isDownwardVertical(path)
        if (rule.direction === 'right') return !isRightward(path)
        return false
      })
      if (bad.length) {
        throw new Error(`Unexpected D2 connection path(s): ${bad.join(', ')}`)
      }
      return
    }

    const paths = pathDataForLines(svg)
    const bad = paths.filter(path => {
      if (rule.allow && !rule.allow.test(path)) return true
      if (rule.direction === 'down') return yDirection(path) <= 0
      return false
    })
    if (bad.length) {
      throw new Error(`Unexpected line path(s): ${bad.join(', ')}`)
    }
  })
}

run('all referenced diagrams are D2-generated', () => {
  const missing = []
  for (const file of walk('content').filter(path => path.endsWith('.mdx'))) {
    const text = readFileSync(join(repo, file), 'utf8')
    for (const match of text.matchAll(/(?:lightSrc|darkSrc)="(\/diagrams\/[^"]+\.svg)"/g)) {
      const output = `public${match[1]}`
      if (!d2OutputMap.has(output)) missing.push(`${file}: ${match[1]}`)
      else {
        const svg = readFileSync(join(repo, output), 'utf8')
        if (!svg.includes('data-d2-version=')) missing.push(`${file}: ${match[1]} is not D2 output`)
      }
    }
  }
  if (missing.length) throw new Error(`Non-D2 diagram reference(s):\n${missing.join('\n')}`)
})

run('Nextra navigation includes current platform surfaces', () => {
  const meta = readFileSync(join(repo, 'app/_meta.global.tsx'), 'utf8')
  const required = [
    "'review-environments': 'Review environments'",
    "'backstage-idp': 'Portal and IDP'",
  ]
  const missing = required.filter(snippet => !meta.includes(snippet))
  if (missing.length) {
    throw new Error(`Missing Nextra navigation entries:\n${missing.join('\n')}`)
  }
})

run('repository map FileTree includes active source trees', () => {
  const mapPath = join(repo, 'content/reference/repository-map.mdx')
  const map = readFileSync(mapPath, 'utf8')
  const tree = map.match(/<FileTree>[\s\S]*<\/FileTree>/)?.[0] ?? ''
  const required = [
    'name="backstage"',
    'name="idp-core"',
    'name="idp-mcp"',
    'name="idp-sdk"',
    'name="platform-mcp"',
    'name="gitea-actions-runner"',
    'name="cluster-policies"',
    'name="sites"',
    'name="use-platform"',
  ]
  const missing = required.filter(snippet => !tree.includes(snippet))
  if (missing.length) {
    throw new Error(`Repository map FileTree missing entries:\n${missing.join('\n')}`)
  }
})

run('review environments page exists', () => {
  const pagePath = join(repo, 'content/operations/review-environments.mdx')
  if (!existsSync(pagePath)) {
    throw new Error('Missing content/operations/review-environments.mdx')
  }
})

for (const [file, theme] of themePairs) {
  run(`theme marker ${file}`, () => {
    const svg = readFileSync(join(repo, file), 'utf8')
    if (!svg.includes(`color-scheme:only ${theme}`)) {
      throw new Error(`Expected color-scheme:only ${theme}`)
    }
    if (/prefers-color-scheme/.test(svg)) {
      throw new Error('SVG must not switch theme through prefers-color-scheme')
    }
  })
}

if (process.exitCode) process.exit(process.exitCode)
