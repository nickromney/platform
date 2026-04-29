import { execFileSync } from 'node:child_process'
import { mkdir, readFile, readdir, writeFile } from 'node:fs/promises'
import { dirname, join, relative } from 'node:path'

const repo = process.cwd()
const checkOnly = process.argv.includes('--check')

const themes = {
  light: 0,
  dark: 200,
}

async function walk(dir, files = []) {
  for (const entry of await readdir(join(repo, dir), { withFileTypes: true })) {
    const path = `${dir}/${entry.name}`
    if (entry.isDirectory()) await walk(path, files)
    else if (entry.name.endsWith('.d2')) files.push(path)
  }
  return files
}

function metadata(source, text) {
  const values = {}
  for (const line of text.split('\n')) {
    const match = line.match(/^#\s*@([a-z-]+)\s+(.+)\s*$/)
    if (match) values[match[1]] = match[2].trim()
  }
  if (!values.light || !values.dark) {
    throw new Error(`${source} must declare # @light and # @dark outputs`)
  }
  return {
    source,
    layout: values.layout || 'elk',
    pad: values.pad || '64',
    outputs: {
      light: values.light,
      dark: values.dark,
    },
  }
}

function requireD2() {
  try {
    execFileSync('d2', ['version'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    })
  } catch {
    throw new Error('D2 CLI is required. Install it with `brew install d2` on macOS, then rerun `bun run media:d2`.')
  }
}

function renderD2(diagram, themeId) {
  return execFileSync(
    'd2',
    [`--layout=${diagram.layout}`, `--theme=${themeId}`, `--pad=${diagram.pad}`, '--no-xml-tag', diagram.source, '-'],
    {
      cwd: repo,
      encoding: 'utf8',
      maxBuffer: 24 * 1024 * 1024,
      stdio: ['ignore', 'pipe', 'pipe'],
    }
  )
}

function postProcessSvg(svg, mode) {
  if (/prefers-color-scheme/.test(svg)) {
    throw new Error('D2 output must be fixed-theme SVG, not prefers-color-scheme SVG. Use --theme, not --dark-theme.')
  }
  if (!svg.includes('data-d2-version=')) {
    throw new Error('Expected a D2-generated SVG.')
  }

  const style = `max-width:100%;height:auto;display:block;color-scheme:only ${mode}`
  return svg.replace('<svg ', `<svg style="${style}" `).trim() + '\n'
}

requireD2()

const diagrams = []
for (const source of await walk('diagrams/d2')) {
  const text = await readFile(join(repo, source), 'utf8')
  diagrams.push(metadata(source, text))
}

const outputsSeen = new Set()

for (const diagram of diagrams) {
  execFileSync('d2', ['validate', diagram.source], {
    cwd: repo,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })

  for (const [mode, output] of Object.entries(diagram.outputs)) {
    const outputPath = join(repo, output)
    const relativeOutput = relative(repo, outputPath)
    if (outputsSeen.has(relativeOutput)) {
      throw new Error(`Multiple D2 sources render ${relativeOutput}`)
    }
    outputsSeen.add(relativeOutput)

    const svg = postProcessSvg(renderD2(diagram, themes[mode]), mode)
    if (checkOnly) {
      const existing = await readFile(outputPath, 'utf8')
      if (existing !== svg) {
        throw new Error(`${output} is stale. Run \`bun run media:d2\`.`)
      }
      console.log(`checked ${output}`)
      continue
    }

    await mkdir(dirname(outputPath), { recursive: true })
    await writeFile(outputPath, svg)
    console.log(`generated ${output}`)
  }
}
