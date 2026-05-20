export interface RuntimeConfig {
  appName?: string;
  environment?: string;
  apiBasePath?: string;
  gatewayURL?: string;
  backendURL?: string;
  managementBasePath?: string;
  networkHops?: NetworkHop[];
}

export interface NetworkHop {
  label: string;
  detail: string;
  role?: string;
  url?: string;
}

export interface PolicyScope {
  scope_type: string;
  scope_name: string;
}

export interface ApiSummary {
  name: string;
  path: string;
  operations?: OperationSummary[];
  policy_scope: PolicyScope;
}

export interface OperationSummary {
  name: string;
  method?: string;
  url_template?: string;
  policy_scope: PolicyScope;
}

export interface RouteSummary {
  name: string;
  path_prefix: string;
  upstream_base_url: string;
  policy_scope?: PolicyScope;
}

export interface ProductSummary {
  id: string;
  name: string;
  require_subscription?: boolean;
}

export interface BackendSummary {
  id: string;
  url: string;
  auth_type?: string;
}

export interface SubscriptionSummary {
  id: string;
  name: string;
  state: string;
  keys?: {
    primary?: string;
    secondary?: string;
  };
  products?: string[];
}

export interface ManagementSummary {
  gateway_policy_scope?: PolicyScope;
  apis?: ApiSummary[];
  routes?: RouteSummary[];
  products?: ProductSummary[];
  backends?: BackendSummary[];
  subscriptions?: SubscriptionSummary[];
}

export interface TraceRecord {
  trace_id: string;
  route?: string;
  status?: number;
  forwarded_proto?: string;
}

export interface TraceList {
  items?: TraceRecord[];
}

export interface ReplayResult {
  trace?: TraceRecord;
  [key: string]: unknown;
}

export interface ApiDiagnostics {
  traceId?: string;
  correlationId?: string;
  requestStartedAt: string;
  responseEndedAt: string;
  durationMs: number;
  requestURL: string;
  reachedURL?: string;
  gatewayURL?: string;
  backendURL?: string;
  status: number;
  networkHops: NetworkHop[];
  serverTiming?: string;
}
