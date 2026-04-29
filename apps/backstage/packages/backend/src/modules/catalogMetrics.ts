import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadAll } from 'js-yaml';

type CatalogEntity = {
  kind?: string;
  metadata?: {
    name?: string;
    annotations?: Record<string, string>;
  };
  spec?: {
    type?: string;
    providesApis?: string[];
    consumesApis?: string[];
  };
};

const DEFAULT_CATALOG_FILES = [
  'catalog/entities.yaml',
  'catalog/apps/platform-mcp/catalog-info.yaml',
  'catalog/apps/subnetcalc/catalog-info.yaml',
  'catalog/apps/apim-simulator/catalog-info.yaml',
  'catalog/apps/sentiment/catalog-info.yaml',
];

function metricNameLabel(value: string | undefined): string {
  return (value || 'unknown').replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function gauge(name: string, labels: Record<string, string>, value: number): string {
  const renderedLabels = Object.entries(labels)
    .map(([key, labelValue]) => `${key}="${metricNameLabel(labelValue)}"`)
    .join(',');
  return `${name}{${renderedLabels}} ${value}`;
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
    const kind = entity.kind || 'unknown';
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
    const type = component.spec?.type || 'unknown';
    componentTypeCounts.set(type, (componentTypeCounts.get(type) || 0) + 1);
  }
  for (const [type, count] of [...componentTypeCounts.entries()].sort()) {
    lines.push(gauge('backstage_catalog_components_total', { type }, count));
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
