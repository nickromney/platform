import { useEffect, useMemo, useState } from "react"

export const DEFAULT_IDP_API_BASE_URL = "https://portal-api.127.0.0.1.sslip.io"

type IdpCatalog = {
  applications: Array<{
    name: string
    owner?: string
    environments?: Array<{ name: string }>
  }>
}

type RuntimePayload = {
  active_runtime: {
    name: string
    description: string
  }
}

class IdpClient {
  private readonly baseUrl: string

  constructor(baseUrl = import.meta.env.VITE_IDP_API_BASE_URL || DEFAULT_IDP_API_BASE_URL) {
    this.baseUrl = baseUrl.replace(/\/+$/, "")
  }

  async getRuntime(): Promise<RuntimePayload> {
    const response = await fetch(`${this.baseUrl}/api/v1/runtime`)
    if (!response.ok) {
      throw new Error(`Portal API ${response.status}`)
    }
    return (await response.json()) as RuntimePayload
  }

  async getCatalog(): Promise<IdpCatalog> {
    const response = await fetch(`${this.baseUrl}/api/v1/catalog/apps`)
    if (!response.ok) {
      throw new Error(`Portal API ${response.status}`)
    }
    return (await response.json()) as IdpCatalog
  }
}

export function App() {
  const client = useMemo(() => new IdpClient(), [])
  const [catalog, setCatalog] = useState<IdpCatalog>({ applications: [] })
  const [runtime, setRuntime] = useState<string>("unknown")
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false

    client
      .getRuntime()
      .then((nextRuntime) => {
        if (!cancelled) {
          setRuntime(nextRuntime.active_runtime.name)
        }
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Unable to load IDP runtime")
        }
      })

    client
      .getCatalog()
      .then((nextCatalog) => {
        if (!cancelled) {
          setCatalog(nextCatalog)
          setError(null)
        }
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Unable to load IDP catalog")
        }
      })

    return () => {
      cancelled = true
    }
  }, [client])

  return (
    <main className="shell">
      <header className="masthead">
        <p className="eyebrow">Internal developer platform</p>
        <h1>Developer Portal</h1>
        <p className="runtime">Runtime: {runtime}</p>
      </header>

      <section aria-labelledby="catalog-heading" className="panel">
        <div className="panel-header">
          <h2 id="catalog-heading">Service catalog</h2>
          <span>{catalog.applications.length} apps</span>
        </div>

        {error ? <p role="alert" className="error">{error}</p> : null}

        <ul className="catalog-list">
          {catalog.applications.map((app) => (
            <li key={app.name}>
              <strong>{app.name}</strong>
              <span>{app.owner ?? "unowned"}</span>
              <small>
                {(app.environments ?? []).map((environment) => environment.name).join(", ") || "no environments"}
              </small>
            </li>
          ))}
        </ul>
      </section>
    </main>
  )
}
