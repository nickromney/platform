import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadAll } from 'js-yaml';

type CatalogEntity = {
  kind?: string;
  metadata?: {
    name?: string;
    annotations?: Record<string, string>;
    links?: Array<{
      title?: string;
      url?: string;
    }>;
  };
  spec?: {
    type?: string;
    lifecycle?: string;
    owner?: string;
    system?: string;
    providesApis?: string[];
    consumesApis?: string[];
  };
};

const DEFAULT_CATALOG_FILES = [
  'catalog/entities.yaml',
  'catalog/apps/idp-core/catalog-info.yaml',
  'catalog/apps/platform-mcp/catalog-info.yaml',
  'catalog/apps/langfuse/catalog-info.yaml',
  'catalog/apps/langfuse-demos/catalog-info.yaml',
  'catalog/apps/chatgpt-sim/catalog-info.yaml',
  'catalog/apps/subnetcalc/catalog-info.yaml',
  'catalog/apps/apim-simulator/catalog-info.yaml',
  'catalog/apps/sentiment/catalog-info.yaml',
];

function metricNameLabel(value: string | undefined): string {
  return (value || 'not_declared').replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function gauge(name: string, labels: Record<string, string>, value: number): string {
  const renderedLabels = Object.entries(labels)
    .map(([key, labelValue]) => `${key}="${metricNameLabel(labelValue)}"`)
    .join(',');
  return `${name}{${renderedLabels}} ${value}`;
}

function linkKind(title: string | undefined, url: string | undefined): string {
  const normalizedTitle = (title || '').toLowerCase();
  const normalizedUrl = url || '';
  if (
    normalizedUrl.includes('/d/') ||
    normalizedTitle.includes('observability') ||
    normalizedTitle.includes('golden signals') ||
    normalizedTitle.includes('grafana')
  ) {
    return 'observability';
  }
  if (normalizedUrl.startsWith('http://') || normalizedUrl.startsWith('https://')) {
    return 'application';
  }
  return 'other';
}

function configuredCatalogFiles(): string[] {
  const root = resolve(process.env.BACKSTAGE_CATALOG_METRICS_ROOT || process.cwd());
  const configured = process.env.BACKSTAGE_CATALOG_METRICS_FILES;
  const relativeFiles = configured
    ? configured.split(',').map(item => item.trim()).filter(Boolean)
    : DEFAULT_CATALOG_FILES;

  return relativeFiles.map(file => resolve(root, file));
}

function loadCatalogEntities(files: string[]): { entities: CatalogEntity[]; missingFiles: string[] } {
  const entities: CatalogEntity[] = [];
  const missingFiles: string[] = [];

  for (const file of files) {
    try {
      const docs = loadAll(readFileSync(file, 'utf8')) as CatalogEntity[];
      entities.push(...docs.filter(doc => doc && typeof doc === 'object'));
    } catch {
      missingFiles.push(file);
    }
  }

  return { entities, missingFiles };
}

export function renderCatalogMetrics(): string {
  const files = configuredCatalogFiles();
  const { entities, missingFiles } = loadCatalogEntities(files);
  const components = entities.filter(entity => entity.kind === 'Component');
  const services = components.filter(entity => entity.spec?.type === 'service');
  const apis = entities.filter(entity => entity.kind === 'API');

  const lines = [
    '# HELP backstage_catalog_entities_total Backstage catalog entities by kind.',
    '# TYPE backstage_catalog_entities_total gauge',
  ];

  const kindCounts = new Map<string, number>();
  for (const entity of entities) {
    const kind = entity.kind || 'not_declared';
    kindCounts.set(kind, (kindCounts.get(kind) || 0) + 1);
  }
  for (const [kind, count] of [...kindCounts.entries()].sort()) {
    lines.push(gauge('backstage_catalog_entities_total', { kind }, count));
  }

  lines.push(
    '# HELP backstage_catalog_components_total Backstage components by spec.type.',
    '# TYPE backstage_catalog_components_total gauge',
  );
  const componentTypeCounts = new Map<string, number>();
  for (const component of components) {
    const type = component.spec?.type || 'not_declared';
    componentTypeCounts.set(type, (componentTypeCounts.get(type) || 0) + 1);
  }
  for (const [type, count] of [...componentTypeCounts.entries()].sort()) {
    lines.push(gauge('backstage_catalog_components_total', { type }, count));
  }

  lines.push(
    '# HELP backstage_catalog_component_locality_total Backstage components with ownership and lifecycle locality labels.',
    '# TYPE backstage_catalog_component_locality_total gauge',
  );
  for (const component of [...components].sort((left, right) =>
    (left.metadata?.name || '').localeCompare(right.metadata?.name || ''),
  )) {
    lines.push(
      gauge(
        'backstage_catalog_component_locality_total',
        {
          component: component.metadata?.name || 'not_declared',
          owner: component.spec?.owner || 'not_declared',
          lifecycle: component.spec?.lifecycle || 'not_declared',
          system: component.spec?.system || 'not_declared',
          type: component.spec?.type || 'not_declared',
        },
        1,
      ),
    );
  }

  const componentLinkCounts = new Map<string, number>();
  for (const component of components) {
    const componentName = component.metadata?.name || 'not_declared';
    for (const link of component.metadata?.links || []) {
      const kind = linkKind(link.title, link.url);
      const key = `${componentName}\u0000${kind}`;
      componentLinkCounts.set(key, (componentLinkCounts.get(key) || 0) + 1);
    }
  }
  lines.push(
    '# HELP backstage_catalog_component_links_total Backstage component links grouped by consumer contract kind.',
    '# TYPE backstage_catalog_component_links_total gauge',
  );
  for (const [key, count] of [...componentLinkCounts.entries()].sort()) {
    const [component, kind] = key.split('\u0000');
    lines.push(gauge('backstage_catalog_component_links_total', { component, kind }, count));
  }

  const annotationMetrics = [
    ['kubernetes_label_selector', 'backstage.io/kubernetes-label-selector'],
    ['source_location', 'backstage.io/source-location'],
    ['techdocs_ref', 'backstage.io/techdocs-ref'],
  ] as const;

  lines.push(
    '# HELP backstage_catalog_service_annotations_total Service components grouped by required annotation state.',
    '# TYPE backstage_catalog_service_annotations_total gauge',
  );
  for (const [annotation, annotationKey] of annotationMetrics) {
    const present = services.filter(service => Boolean(service.metadata?.annotations?.[annotationKey])).length;
    lines.push(gauge('backstage_catalog_service_annotations_total', { annotation, state: 'present' }, present));
    lines.push(
      gauge('backstage_catalog_service_annotations_total', {
        annotation,
        state: 'missing',
      }, services.length - present),
    );
  }

  lines.push(
    '# HELP backstage_catalog_apis_total Backstage API entities.',
    '# TYPE backstage_catalog_apis_total gauge',
    `backstage_catalog_apis_total ${apis.length}`,
    '# HELP backstage_catalog_api_relationships_total Component API relationships.',
    '# TYPE backstage_catalog_api_relationships_total gauge',
    `backstage_catalog_api_relationships_total{relationship="provides"} ${components.reduce((count, component) => count + (component.spec?.providesApis?.length || 0), 0)}`,
    `backstage_catalog_api_relationships_total{relationship="consumes"} ${components.reduce((count, component) => count + (component.spec?.consumesApis?.length || 0), 0)}`,
    '# HELP backstage_catalog_locations_missing_total Configured catalog files that could not be read by the metrics endpoint.',
    '# TYPE backstage_catalog_locations_missing_total gauge',
    `backstage_catalog_locations_missing_total ${missingFiles.length}`,
  );

  return `${lines.join('\n')}\n`;
}

export function startCatalogMetricsServer(): void {
  const port = Number(process.env.BACKSTAGE_CATALOG_METRICS_PORT || '9465');

  createServer((request, response) => {
    if (request.url === '/health') {
      response.writeHead(200, { 'content-type': 'text/plain; charset=utf-8' });
      response.end('ok\n');
      return;
    }

    if (request.url !== '/metrics') {
      response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      response.end('not found\n');
      return;
    }

    response.writeHead(200, { 'content-type': 'text/plain; version=0.0.4; charset=utf-8' });
    response.end(renderCatalogMetrics());
  }).listen(port, '0.0.0.0');
}
