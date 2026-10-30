import {readFileSync} from 'node:fs'
import {resolve} from 'node:path'
import {fileURLToPath} from 'node:url'

// Advisory snapshot: 2026-10-28. This checks lockfile resolution, not deployment.
// https://github.com/advisories/GHSA-673q-mjm6-r5xr
// https://github.com/advisories/GHSA-2464-fhr4-w9xw
// https://github.com/advisories/GHSA-p3m5-59mp-jv5r
function version(entry, name) {
  if (!Array.isArray(entry) || typeof entry[0] !== 'string') throw new Error(`missing or invalid ${name} lock entry`)
  const match = entry[0].match(new RegExp(`^${name}@(\\d+)\\.(\\d+)\\.(\\d+)$`))
  if (!match) throw new Error(`invalid ${name} version: ${entry[0]}`)
  return match.slice(1).map(Number)
}

function atLeast(actual, floor) {
  for (let i = 0; i < floor.length; i++) {
    if (actual[i] !== floor[i]) return actual[i] > floor[i]
  }
  return true
}

export function checkNextAdvisories(source) {
  const lock = Bun.JSONC.parse(source)
  const packages = lock?.packages
  if (!packages || typeof packages !== 'object' || Array.isArray(packages)) throw new Error('missing lockfile packages')
  const packageParts = key => key.match(/@[^/]+\/[^/]+|[^/]+/g) ?? []
  const nextKeys = Object.keys(packages).filter(key => packageParts(key).at(-1) === 'next')
  if (!nextKeys.includes('next')) throw new Error('missing root next lock entry')
  for (const key of nextKeys) {
    const next = version(packages[key], 'next')
    if (next[0] !== 16 || !atLeast(next, [16, 4, 1])) throw new Error(`${key} must resolve to reviewed Next.js 16.4.1 or later on 16.x`)
    const metadata = packages[key][2]
    const sharpRange = metadata?.optionalDependencies?.sharp ?? metadata?.dependencies?.sharp
    if (typeof sharpRange !== 'string') throw new Error(`${key} does not declare sharp`)
    const parts = packageParts(key)
    let sharpKey
    while (parts.length) {
      const candidate = `${parts.join('/')}/sharp`
      if (Object.hasOwn(packages, candidate)) { sharpKey = candidate; break }
      parts.pop()
    }
    sharpKey ||= 'sharp'
    const sharp = version(packages[sharpKey], 'sharp')
    if (!Bun.semver.satisfies(sharp.join('.'), sharpRange)) throw new Error(`${sharpKey} does not satisfy ${key}'s sharp range ${sharpRange}`)
    if (sharp[0] !== 0 || !atLeast(sharp, [0, 35, 5])) throw new Error(`${sharpKey} must resolve to reviewed sharp 0.35.5 or later on 0.x`)
  }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    checkNextAdvisories(readFileSync(process.argv[2] || 'bun.lock', 'utf8'))
    console.log('Next.js advisory lockfile check passed (snapshot 2026-10-28; deployment not checked)')
  } catch (error) {
    console.error(`Next.js advisory lockfile check failed: ${error.message}`)
    process.exitCode = 1
  }
}
