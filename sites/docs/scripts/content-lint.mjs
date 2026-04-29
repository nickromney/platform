import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

const root = join(process.cwd(), 'content')
const pages = []

function walk(dir) {
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry)
    if (statSync(path).isDirectory()) walk(path)
    else if (entry.endsWith('.mdx')) pages.push(path)
  }
}

walk(root)

const failures = []
for (const page of pages) {
  const text = readFileSync(page, 'utf8')
  const hasHeading = /^#\s+/m.test(text)
  const hasExample = /```(bash|sh|shell|yaml|hcl|tsx|ts|js|python)|<FileTree>|<FileTree\.|<ThemeImage/.test(text)
  const hasCrossLink = /\]\((\.\.?\/|\/)/.test(text)
  const hasPitfall = /(warning|Common mistake|Gotcha|Pitfall|Troubleshooting)/i.test(text)
  if (!hasHeading) failures.push(`${page}: missing h1`)
  if (text.length > 900 && !hasExample) failures.push(`${page}: substantial page without code or diagram`)
  if (text.length > 900 && !hasCrossLink) failures.push(`${page}: substantial page without local cross-link`)
  if (text.length > 1200 && !hasPitfall) failures.push(`${page}: substantial page without warning/pitfall language`)
}

if (failures.length) {
  console.error(failures.join('\n'))
  process.exit(1)
}

console.log(`content lint passed for ${pages.length} pages`)
