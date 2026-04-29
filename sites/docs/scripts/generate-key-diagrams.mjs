import { mkdir, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

const outputRoot = join(process.cwd(), 'public', 'diagrams')
const generatedRoot = join(outputRoot, 'generated')

const themes = {
  light: {
    bg: '#f7f9fc',
    surface: '#ffffff',
    surfaceAlt: '#f1f5f9',
    softTeal: '#dcfdfa',
    softAmber: '#fff7ed',
    softBlue: '#eff6ff',
    text: '#102033',
    muted: '#526173',
    border: '#b6c2d0',
    line: '#627184',
    teal: '#0f766e',
    amber: '#b45309',
    blue: '#2563eb',
    green: '#15803d',
    shadow: '#d7dee8',
  },
  dark: {
    bg: '#07111c',
    surface: '#101827',
    surfaceAlt: '#0c1422',
    softTeal: '#0f2f35',
    softAmber: '#33220f',
    softBlue: '#10233f',
    text: '#f7fbff',
    muted: '#b8c4d2',
    border: '#43536a',
    line: '#9aa8b8',
    teal: '#5eead4',
    amber: '#fbbf24',
    blue: '#93c5fd',
    green: '#86efac',
    shadow: '#020617',
  },
}

function escapeXml(value) {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
}

function lines(x, y, items, theme, options = {}) {
  const {
    size = 20,
    weight = 520,
    fill = theme.text,
    gap = Math.round(size * 1.35),
    klass = 'copy',
  } = options

  return items
    .map((item, index) => `<text x="${x}" y="${y + index * gap}" class="${klass}" fill="${fill}" font-size="${size}" font-weight="${weight}">${escapeXml(item)}</text>`)
    .join('\n')
}

function card({ x, y, w, h, title, body, theme, fill, accent, icon = 'circle', titleSize = 23 }) {
  const accentColor = accent || theme.teal
  const iconShape = icon === 'diamond'
    ? `<rect x="${x + 24}" y="${y + 29}" width="18" height="18" fill="${accentColor}" transform="rotate(45 ${x + 33} ${y + 38})" rx="3"/>`
    : `<circle cx="${x + 33}" cy="${y + 38}" r="9" fill="${accentColor}"/>`

  return `
  <rect x="${x + 3}" y="${y + 5}" width="${w}" height="${h}" rx="14" fill="${theme.shadow}" opacity="0.22"/>
  <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="14" fill="${fill || theme.surface}" stroke="${theme.border}" stroke-width="1.5"/>
  ${iconShape}
  <text x="${x + 55}" y="${y + 46}" class="title" fill="${theme.text}" font-size="${titleSize}" font-weight="760">${escapeXml(title)}</text>
  ${lines(x + 32, y + 82, body, theme, { size: 18, weight: 520, fill: theme.muted, gap: 25 })}`
}

function pill(x, y, label, theme, fill, stroke) {
  const width = Math.max(124, Math.round(label.length * 8.2 + 44))
  return `
  <rect x="${x}" y="${y}" width="${width}" height="44" rx="22" fill="${fill}" stroke="${stroke}" stroke-width="1.2"/>
  <text x="${x + 17}" y="${y + 28}" class="pill" fill="${theme.text}" font-size="16" font-weight="700">${escapeXml(label)}</text>`
}

function baseSvg({ width, height, theme, title, desc, body }) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" style="max-width:100%;height:auto;display:block;color-scheme:only ${theme === themes.dark ? 'dark' : 'light'}" viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="title desc">
  <title id="title">${escapeXml(title)}</title>
  <desc id="desc">${escapeXml(desc)}</desc>
  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto">
      <path d="M 0 0 L 10 5 L 0 10 z" fill="${theme.line}"/>
    </marker>
    <linearGradient id="rail" x1="0" x2="1" y1="0" y2="1">
      <stop offset="0" stop-color="${theme.softTeal}"/>
      <stop offset="1" stop-color="${theme.softBlue}"/>
    </linearGradient>
  </defs>
  <rect width="${width}" height="${height}" fill="${theme.bg}"/>
  <style>
    text { font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; letter-spacing: 0; }
    .display { font-weight: 780; }
    .copy { paint-order: stroke; stroke: transparent; stroke-width: 0; }
    .line { stroke: ${theme.line}; stroke-width: 3; fill: none; marker-end: url(#arrow); stroke-linecap: round; stroke-linejoin: round; }
    .rail { stroke: ${theme.border}; stroke-width: 1.4; stroke-dasharray: 5 9; fill: none; }
  </style>
${body}
</svg>
`
}

function workbench(theme) {
  const body = `
  <path d="M48 134 H1232" class="rail"/>
  <text x="56" y="66" class="display" fill="${theme.text}" font-size="38">Inspectable local platform</text>
  ${lines(56, 104, ['A laptop-scale IDP loop with explicit stages, pins, policy, identity, and observability.'], theme, { size: 20, fill: theme.muted })}
  ${pill(965, 48, 'Kind default', theme, theme.softTeal, theme.teal)}
  ${pill(1100, 48, 'Dex SSO', theme, theme.softBlue, theme.blue)}

  ${card({ x: 56, y: 176, w: 250, h: 150, title: 'Operator', body: ['Make targets', 'Shell preflight', 'Reset and health checks'], theme, fill: theme.surface, accent: theme.teal })}
  ${card({ x: 342, y: 176, w: 245, h: 150, title: 'Runtime', body: ['Kind reference path', 'Lima and Slicer options', 'Kubeconfig and ports'], theme, fill: theme.softAmber, accent: theme.amber, icon: 'diamond' })}

  <rect x="640" y="138" width="310" height="262" rx="18" fill="url(#rail)" stroke="${theme.border}" stroke-width="1.5"/>
  <text x="674" y="190" class="title" fill="${theme.text}" font-size="26" font-weight="780">Platform core</text>
  ${lines(674, 232, ['Cilium + Hubble', 'Gateway API + local TLS', 'Prometheus + Grafana', '+ VictoriaLogs', 'Kyverno policy controls'], theme, { size: 19, fill: theme.muted, gap: 28 })}
  <circle cx="915" cy="178" r="12" fill="${theme.teal}"/>
  <circle cx="892" cy="178" r="12" fill="${theme.blue}" opacity="0.9"/>
  <circle cx="869" cy="178" r="12" fill="${theme.green}" opacity="0.9"/>

  ${card({ x: 1010, y: 132, w: 214, h: 128, title: 'GitOps', body: ['Gitea app repos', 'Argo CD sync'], theme, fill: theme.surface, accent: theme.amber, titleSize: 22 })}
  ${card({ x: 1010, y: 320, w: 214, h: 128, title: 'Apps', body: ['Subnetcalc', 'Sentiment probes'], theme, fill: theme.surface, accent: theme.green, titleSize: 22 })}

  <path d="M306 251 H342" class="line"/>
  <path d="M587 251 H640" class="line"/>
  <path d="M950 214 H1010" class="line"/>
  <path d="M950 337 C972 337 981 384 1010 384" class="line"/>
  <path d="M1117 260 V320" class="line"/>

  <rect x="76" y="486" width="1128" height="96" rx="18" fill="${theme.surface}" stroke="${theme.border}" stroke-width="1.5"/>
  <text x="112" y="526" class="title" fill="${theme.text}" font-size="23" font-weight="760">What the platform proves</text>
  ${lines(112, 558, ['Configuration, orchestration, environments, delivery, and access control.'], theme, { size: 19, fill: theme.muted })}
  ${pill(870, 516, 'Pinned versions', theme, theme.softBlue, theme.blue)}
  ${pill(1032, 516, 'Policy evidence', theme, theme.softTeal, theme.teal)}
`

  return baseSvg({
    width: 1280,
    height: 640,
    theme,
    title: 'Local platform workbench architecture',
    desc: 'Operator commands assemble a local runtime, Kubernetes platform control plane, GitOps delivery, security controls, and sample applications.',
    body,
  })
}

function indexFlow(theme) {
  const body = `
  <text x="48" y="62" class="display" fill="${theme.text}" font-size="34">Local platform flow</text>
  ${lines(48, 96, ['A staged route from host commands to reconciled workloads, with version and hardening checks around it.'], theme, { size: 18, fill: theme.muted })}

  ${card({ x: 56, y: 142, w: 260, h: 128, title: 'Host commands', body: ['make -C kubernetes/kind', 'preflight, plan, apply'], theme, fill: theme.surface, accent: theme.teal, titleSize: 22 })}
  ${card({ x: 368, y: 142, w: 260, h: 128, title: 'Runtime', body: ['Kind first', 'Lima and Slicer paths'], theme, fill: theme.softAmber, accent: theme.amber, icon: 'diamond', titleSize: 22 })}
  ${card({ x: 680, y: 142, w: 260, h: 128, title: 'IaC engine', body: ['Terragrunt wrapper', 'OpenTofu by default'], theme, fill: theme.softBlue, accent: theme.blue, titleSize: 22 })}

  ${card({ x: 92, y: 360, w: 292, h: 136, title: 'Platform core', body: ['Cilium, Hubble, Gateway API', 'TLS, policy, observability'], theme, fill: theme.softTeal, accent: theme.teal })}
  ${card({ x: 558, y: 330, w: 324, h: 128, title: 'GitOps', body: ['Gitea stores rendered intent', 'Argo CD reconciles drift'], theme, fill: theme.softAmber, accent: theme.amber })}
  ${card({ x: 558, y: 496, w: 324, h: 128, title: 'Applications', body: ['Subnetcalc and Sentiment', 'prove the path'], theme, fill: theme.surface, accent: theme.green })}

  <path d="M316 206 H368" class="line"/>
  <path d="M628 206 H680" class="line"/>
  <path d="M810 270 C810 326 505 318 330 360" class="line"/>
  <path d="M384 428 H558" class="line"/>
  <path d="M720 458 V496" class="line"/>

  <rect x="56" y="536" width="396" height="64" rx="14" fill="${theme.surfaceAlt}" stroke="${theme.border}" stroke-width="1.4"/>
  ${lines(84, 562, ['Version pins and cooldown gates', 'keep upgrades deliberate.'], theme, { size: 17, fill: theme.muted, gap: 22 })}
`

  return baseSvg({
    width: 960,
    height: 640,
    theme,
    title: 'Local platform flow',
    desc: 'Operator commands select a local runtime, apply the shared platform stack, then hand off to GitOps and sample applications.',
    body,
  })
}

function arrow(x1, y1, x2, y2, extra = '') {
  return `<path d="M${x1} ${y1} H${x2}" class="line" ${extra}/>`
}

function patternMap(theme) {
  const body = `
  <text x="56" y="66" class="display" fill="${theme.text}" font-size="36">Application pattern map</text>
  ${lines(56, 100, ['Two sample apps exercise different hosting, identity, routing, and API boundaries.'], theme, { size: 19, fill: theme.muted })}

  <rect x="40" y="132" width="1200" height="230" rx="18" fill="${theme.surface}" stroke="${theme.border}" stroke-width="1.5"/>
  <text x="86" y="174" fill="${theme.teal}" font-size="18" font-weight="780">Subnetcalc lane</text>
  ${card({ x: 80, y: 196, w: 255, h: 132, title: 'Frontend variants', body: ['React/Vite/static/Flask', 'Easy Auth variants'], theme, fill: theme.surfaceAlt, accent: theme.teal, titleSize: 20 })}
  ${card({ x: 376, y: 196, w: 240, h: 132, title: 'APIM simulator', body: ['Identity gate', 'API mediation'], theme, fill: theme.softBlue, accent: theme.blue, titleSize: 20 })}
  ${card({ x: 656, y: 196, w: 250, h: 132, title: 'FastAPI backends', body: ['JWT checks', 'backend forwarding'], theme, fill: theme.softAmber, accent: theme.amber, titleSize: 20 })}
  ${card({ x: 946, y: 196, w: 270, h: 132, title: 'Subnet rules', body: ['CIDR logic', 'cloud reservation checks'], theme, fill: theme.softTeal, accent: theme.green, titleSize: 20 })}
  ${arrow(335, 257, 376, 257)}
  ${arrow(616, 257, 656, 257)}
  ${arrow(906, 257, 946, 257)}

  <rect x="40" y="390" width="1200" height="230" rx="18" fill="${theme.surface}" stroke="${theme.border}" stroke-width="1.5"/>
  <text x="86" y="432" fill="${theme.amber}" font-size="18" font-weight="780">Sentiment lane</text>
  ${card({ x: 80, y: 454, w: 255, h: 132, title: 'Static UI', body: ['Browser session', 'local TLS edge'], theme, fill: theme.surfaceAlt, accent: theme.teal, titleSize: 20 })}
  ${card({ x: 376, y: 454, w: 240, h: 132, title: 'oauth2-proxy', body: ['Session cookie', 'token forwarding'], theme, fill: theme.softBlue, accent: theme.blue, titleSize: 20 })}
  ${card({ x: 656, y: 454, w: 250, h: 132, title: 'Edge router', body: ['UI route', '/api/* split'], theme, fill: theme.softAmber, accent: theme.amber, titleSize: 20 })}
  ${card({ x: 946, y: 454, w: 270, h: 132, title: 'Sentiment API', body: ['model warmup', 'classifier response'], theme, fill: theme.softTeal, accent: theme.green, titleSize: 20 })}
  ${arrow(335, 515, 376, 515)}
  ${arrow(616, 515, 656, 515)}
  ${arrow(906, 515, 946, 515)}

  <text x="86" y="700" fill="${theme.muted}" font-size="17" font-weight="700">Supporting paths</text>
  <rect x="240" y="666" width="270" height="52" rx="14" fill="${theme.softAmber}" stroke="${theme.border}" stroke-width="1.4"/>
  <text x="272" y="699" fill="${theme.text}" font-size="18" font-weight="740">Keycloak compose path</text>

  <rect x="532" y="666" width="270" height="52" rx="14" fill="${theme.softBlue}" stroke="${theme.border}" stroke-width="1.4"/>
  <text x="564" y="699" fill="${theme.text}" font-size="18" font-weight="740">Kubernetes GitOps path</text>

  <rect x="824" y="666" width="290" height="52" rx="14" fill="${theme.softTeal}" stroke="${theme.border}" stroke-width="1.4"/>
  <text x="856" y="699" fill="${theme.text}" font-size="18" font-weight="740">Policy and telemetry path</text>
`

  return baseSvg({
    width: 1280,
    height: 760,
    theme,
    title: 'Application pattern map',
    desc: 'Subnetcalc and Sentiment application pathways showing frontend, identity, edge, backend, and domain responsibilities.',
    body,
  })
}

function stageCard({ x, y, w, h, number, title, detail, theme, fill, accent }) {
  return `
  <rect x="${x + 3}" y="${y + 5}" width="${w}" height="${h}" rx="14" fill="${theme.shadow}" opacity="0.22"/>
  <rect x="${x}" y="${y}" width="${w}" height="${h}" rx="14" fill="${fill}" stroke="${theme.border}" stroke-width="1.5"/>
  <text x="${x + 18}" y="${y + 34}" fill="${accent}" font-size="18" font-weight="800">${number}</text>
  <text x="${x + 18}" y="${y + 66}" fill="${theme.text}" font-size="19" font-weight="780">${escapeXml(title)}</text>
  ${lines(x + 18, y + 94, detail, theme, { size: 15, weight: 620, fill: theme.muted, gap: 21 })}`
}

function stageLadder(theme) {
  const stages = [
    ['100', 'Cluster bootstrap', 'Runtime exists; Kind has no CNI yet.', theme.surfaceAlt, theme.teal, 'Foundation'],
    ['200', 'Cilium', 'Pod networking becomes real.', theme.softTeal, theme.teal, 'Foundation'],
    ['300', 'Hubble', 'Network visibility appears.', theme.softBlue, theme.blue, 'Foundation'],
    ['400', 'Argo CD core', 'GitOps control plane starts.', theme.softAmber, theme.amber, 'Control plane'],
    ['500', 'Gitea + controllers', 'Local Git server and richer Argo behaviour.', theme.surfaceAlt, theme.teal, 'Control plane'],
    ['600', 'Policies and certificates', 'Kyverno, cert-manager, and Cilium policy controls.', theme.softTeal, theme.green, 'Control plane'],
    ['700', 'Application repositories', 'Workload sources can be reconciled.', theme.softBlue, theme.blue, 'Operator path'],
    ['800', 'Gateway TLS and observability', 'Headlamp, HTTPS, Prometheus, Grafana, and VictoriaLogs.', theme.softAmber, theme.amber, 'Operator path'],
    ['900', 'SSO', 'Dex and oauth2-proxy protect the admin experience.', theme.softTeal, theme.teal, 'Operator path'],
  ]
  const cardX = 190
  const cardW = 760
  const cardH = 78
  const startY = 188
  const gap = 28
  const railX = 112
  let body = `
  <text x="56" y="66" class="display" fill="${theme.text}" font-size="36">Stage ladder</text>
  ${lines(56, 101, ['Stages are cumulative target shapes. Higher stages include everything before them.'], theme, { size: 19, fill: theme.muted })}
  <rect x="56" y="126" width="1088" height="50" rx="16" fill="${theme.surface}" stroke="${theme.border}" stroke-width="1.4"/>
  <text x="84" y="155" fill="${theme.text}" font-size="17" font-weight="740">Apply stage 900 as desired state. It includes stages 100 through 800.</text>
  ${pill(822, 130, 'Kind default', theme, theme.softTeal, theme.teal)}
  ${pill(958, 130, 'Lima / Slicer converge after 100', theme, theme.softBlue, theme.blue)}
  <path d="M${railX} ${startY + 16} V${startY + (stages.length - 1) * (cardH + gap) + cardH - 16}" stroke="${theme.line}" stroke-width="4" stroke-linecap="round" opacity="0.48"/>
`

  stages.forEach(([number, title, detail, fill, accent, phase], index) => {
    const y = startY + index * (cardH + gap)
    const numberY = y + 49
    body += `
  <circle cx="${railX}" cy="${y + cardH / 2}" r="18" fill="${fill}" stroke="${accent}" stroke-width="2"/>
  <text x="${railX}" y="${numberY}" text-anchor="middle" fill="${theme.text}" font-size="16" font-weight="820">${number}</text>
  <rect x="${cardX + 3}" y="${y + 5}" width="${cardW}" height="${cardH}" rx="14" fill="${theme.shadow}" opacity="0.22"/>
  <rect x="${cardX}" y="${y}" width="${cardW}" height="${cardH}" rx="14" fill="${fill}" stroke="${theme.border}" stroke-width="1.5"/>
  <text x="${cardX + 30}" y="${y + 32}" fill="${theme.text}" font-size="20" font-weight="780">${escapeXml(title)}</text>
  <text x="${cardX + 30}" y="${y + 59}" fill="${theme.muted}" font-size="16" font-weight="620">${escapeXml(detail)}</text>
  <text x="${cardX + cardW + 48}" y="${y + 45}" fill="${accent}" font-size="16" font-weight="760">${escapeXml(phase)}</text>`
    if (index < stages.length - 1) {
      body += `<path d="M${railX} ${y + cardH / 2 + 19} V${y + cardH + gap - 19}" class="line"/>`
    }
  })

  return baseSvg({
    width: 1280,
    height: 1160,
    theme,
    title: 'Stage ladder',
    desc: 'Cumulative platform stages from cluster bootstrap to SSO, shown as a single left-to-right sequence.',
    body,
  })
}

await mkdir(outputRoot, { recursive: true })
await mkdir(generatedRoot, { recursive: true })

await writeFile(join(outputRoot, 'idp-local-workbench.svg'), workbench(themes.light))
await writeFile(join(outputRoot, 'idp-local-workbench-dark.svg'), workbench(themes.dark))
await writeFile(join(generatedRoot, 'index-1-light.svg'), indexFlow(themes.light))
await writeFile(join(generatedRoot, 'index-1-dark.svg'), indexFlow(themes.dark))
await writeFile(join(generatedRoot, 'apps-patterns-1-light.svg'), patternMap(themes.light))
await writeFile(join(generatedRoot, 'apps-patterns-1-dark.svg'), patternMap(themes.dark))
await writeFile(join(generatedRoot, 'concepts-stage-ladder-1-light.svg'), stageLadder(themes.light))
await writeFile(join(generatedRoot, 'concepts-stage-ladder-1-dark.svg'), stageLadder(themes.dark))

console.log('generated key diagrams')
