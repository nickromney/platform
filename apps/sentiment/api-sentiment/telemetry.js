import process from 'node:process'

import { diag, DiagConsoleLogger, DiagLogLevel } from '@opentelemetry/api'
import apiLogs from '@opentelemetry/api-logs'
import autoInstr from '@opentelemetry/auto-instrumentations-node'
import logsExporter from '@opentelemetry/exporter-logs-otlp-http'
import metricsExporter from '@opentelemetry/exporter-metrics-otlp-http'
import tracesExporter from '@opentelemetry/exporter-trace-otlp-http'
import { resourceFromAttributes } from '@opentelemetry/resources'
import sdkLogsPkg from '@opentelemetry/sdk-logs'
import sdkMetricsPkg from '@opentelemetry/sdk-metrics'
import sdkNodePkg from '@opentelemetry/sdk-node'

const { logs } = apiLogs
const { getNodeAutoInstrumentations } = autoInstr
const { OTLPLogExporter } = logsExporter
const { OTLPMetricExporter } = metricsExporter
const { OTLPTraceExporter } = tracesExporter
const { LoggerProvider, BatchLogRecordProcessor } = sdkLogsPkg
const { PeriodicExportingMetricReader } = sdkMetricsPkg
const { NodeSDK } = sdkNodePkg

const otlpEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT
if (!otlpEndpoint) {
  // Allow running locally without a collector.
  // When OTEL_EXPORTER_OTLP_ENDPOINT is configured, we enable full telemetry.
  // eslint-disable-next-line no-console
  console.log('telemetry disabled (OTEL_EXPORTER_OTLP_ENDPOINT not set)')
} else {
  diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.ERROR)

  const serviceName = process.env.OTEL_SERVICE_NAME || 'sentiment-api'
  const resource = resourceFromAttributes({ 'service.name': serviceName })

  const metricReader = new PeriodicExportingMetricReader({
    exporter: new OTLPMetricExporter(),
    exportIntervalMillis: 60_000,
  })

  const loggerProvider = new LoggerProvider({
    resource,
    processors: [new BatchLogRecordProcessor(new OTLPLogExporter())],
  })
  logs.setGlobalLoggerProvider(loggerProvider)

  const sdk = new NodeSDK({
    resource,
    traceExporter: new OTLPTraceExporter(),
    metricReader,
    instrumentations: [
      getNodeAutoInstrumentations({
        '@opentelemetry/instrumentation-undici': {
          enabled: false,
        },
      }),
    ],
  })

  await sdk.start()

  const shutdown = async () => {
    await Promise.allSettled([sdk.shutdown(), loggerProvider.shutdown()])
  }

  process.once('SIGINT', shutdown)
  process.once('SIGTERM', shutdown)
}
