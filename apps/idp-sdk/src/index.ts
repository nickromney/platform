export const DEFAULT_IDP_API_BASE_URL = "https://portal-api.127.0.0.1.sslip.io"

export type IdpEnvironmentRequest = {
  runtime?: string
  app: string
  environment: string
  environment_type?: string
}

export type IdpApplication = {
  name: string
  owner?: string
  environments?: Array<{ name: string }>
}

export type IdpCatalog = {
  applications: IdpApplication[]
}

export type IdpRuntime = {
  active_runtime: {
    name: string
    description: string
  }
}

export type IdpWorkflowResponse = {
  dry_run: boolean
  action: string
  runtime: string
  plan: {
    summary: string
    commands: string[]
    manifests: string[]
  }
}

export type IdpDeploymentRequest = {
  runtime?: string
  app: string
  environment: string
  image?: string
}

export class IdpClient {
  private readonly baseUrl: string
  private readonly fetchImpl: typeof fetch

  constructor(options: { baseUrl?: string; fetchImpl?: typeof fetch } = {}) {
    this.baseUrl = (options.baseUrl ?? DEFAULT_IDP_API_BASE_URL).replace(/\/+$/, "")
    this.fetchImpl = options.fetchImpl ?? fetch
  }

  async getRuntime(): Promise<IdpRuntime> {
    return this.request<IdpRuntime>("/api/v1/runtime")
  }

  async listApps(): Promise<IdpCatalog> {
    return this.request<IdpCatalog>("/api/v1/catalog/apps")
  }

  async getApp(app: string): Promise<IdpApplication> {
    return this.request<IdpApplication>(`/api/v1/catalog/apps/${encodeURIComponent(app)}`)
  }

  async createEnvironment(request: IdpEnvironmentRequest, dryRun = true): Promise<IdpWorkflowResponse> {
    return this.request<IdpWorkflowResponse>(`/api/v1/environments?dry_run=${String(dryRun)}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ runtime: "kind", ...request }),
    })
  }

  async promoteDeployment(request: IdpDeploymentRequest, dryRun = true): Promise<IdpWorkflowResponse> {
    return this.request<IdpWorkflowResponse>(`/api/v1/deployments/promote?dry_run=${String(dryRun)}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ runtime: "kind", ...request }),
    })
  }

  private async request<T>(path: string, init?: RequestInit): Promise<T> {
    const response = await this.fetchImpl(`${this.baseUrl}${path}`, { credentials: "include", ...init })
    if (!response.ok) {
      const body = await response.text().catch(() => "")
      throw new Error(`Portal API ${response.status}: ${body || response.statusText}`)
    }

    return (await response.json()) as T
  }
}
