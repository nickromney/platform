package app

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"sort"
	"strings"
	"sync"
)

type TraceRecord struct {
	TraceID         string            `json:"trace_id"`
	Method          string            `json:"method"`
	Path            string            `json:"path"`
	RouteName       string            `json:"route_name"`
	UpstreamURL     string            `json:"upstream_url"`
	StatusCode      int               `json:"status_code"`
	StartedAt       string            `json:"started_at"`
	DurationMillis  int64             `json:"duration_ms"`
	RequestHeaders  map[string]string `json:"request_headers,omitempty"`
	ResponseHeaders map[string]string `json:"response_headers,omitempty"`
	Error           string            `json:"error,omitempty"`
}

type traceStore struct {
	mu    sync.RWMutex
	limit int
	items []TraceRecord
}

func newTraceStore(limit int) *traceStore {
	return &traceStore{limit: limit}
}

func (s *traceStore) add(trace TraceRecord) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.items = append([]TraceRecord{trace}, s.items...)
	if len(s.items) > s.limit {
		s.items = s.items[:s.limit]
	}
}

func (s *traceStore) list() []TraceRecord {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]TraceRecord, len(s.items))
	copy(out, s.items)
	return out
}

func (s *server) summary(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"service":              map[string]any{"name": "apim-simulator", "display_name": "Local APIM Simulator"},
		"apis":                 apiSummaries(s.cfg.APIs),
		"routes":               routeSummaries(s.cfg.Routes),
		"products":             productSummaries(s.cfg.Products),
		"named_values":         namedValueSummaries(s.cfg.NamedValues),
		"subscriptions":        subscriptionSummaries(s.cfg.Subscriptions.Items),
		"backends":             backendSummaries(s.cfg),
		"gateway_policy_scope": map[string]string{"scope_type": "gateway", "scope_name": "global"},
		"policy_scopes":        policyScopes(s.cfg),
	})
}

func (s *server) serviceProjection(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"service": map[string]any{
			"name":                "apim-simulator",
			"display_name":        "Local APIM Simulator",
			"api_count":           len(s.cfg.APIs),
			"product_count":       len(s.cfg.Products),
			"subscription_count":  len(s.cfg.Subscriptions.Items),
			"named_value_count":   len(s.cfg.NamedValues),
			"materialized_routes": len(s.cfg.Routes),
		},
	})
}

func (s *server) listAPIs(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"items": apiSummaries(s.cfg.APIs)})
}

func (s *server) upsertAPI(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		ID string `json:"id"`
		APIConfig
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid API payload"})
		return
	}
	id := firstString(r.PathValue("id"), payload.ID, payload.Name)
	if id == "" || payload.Path == "" || payload.UpstreamBaseURL == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "API id, path, and upstream_base_url are required"})
		return
	}
	s.mu.Lock()
	s.cfg.APIs = cloneMap(s.cfg.APIs)
	s.cfg.APIs[id] = payload.APIConfig
	s.cfg.Routes = routesFromAPIsWithExplicit(s.cfg.APIs, s.cfg.Routes)
	api := s.cfg.APIs[id]
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{"id": id, "api": api})
}

func (s *server) deleteAPI(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	s.mu.Lock()
	if _, ok := s.cfg.APIs[id]; !ok {
		s.mu.Unlock()
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "API not found"})
		return
	}
	s.cfg.APIs = cloneMap(s.cfg.APIs)
	delete(s.cfg.APIs, id)
	s.cfg.Routes = routesFromAPIsWithExplicit(s.cfg.APIs, s.cfg.Routes)
	s.mu.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) listProducts(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"items": productSummaries(s.cfg.Products)})
}

func (s *server) upsertProduct(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		ID string `json:"id"`
		ProductConfig
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid product payload"})
		return
	}
	id := firstString(r.PathValue("id"), payload.ID, payload.Name)
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Product id is required"})
		return
	}
	s.mu.Lock()
	s.cfg.Products = cloneMap(s.cfg.Products)
	s.cfg.Products[id] = payload.ProductConfig
	product := s.cfg.Products[id]
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{"id": id, "product": product})
}

func (s *server) deleteProduct(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	s.mu.Lock()
	if _, ok := s.cfg.Products[id]; !ok {
		s.mu.Unlock()
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Product not found"})
		return
	}
	s.cfg.Products = cloneMap(s.cfg.Products)
	delete(s.cfg.Products, id)
	unlinkProduct(s.cfg.Subscriptions.Items, s.cfg.APIs, s.cfg.Routes, id)
	s.mu.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) listSubscriptions(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"items": subscriptionSummaries(s.cfg.Subscriptions.Items)})
}

func (s *server) upsertSubscription(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		ID string `json:"id"`
		Subscription
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid subscription payload"})
		return
	}
	id := firstString(r.PathValue("id"), payload.ID, payload.Subscription.ID)
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Subscription id is required"})
		return
	}
	sub := payload.Subscription
	if sub.ID == "" {
		sub.ID = id
	}
	if sub.State == "" {
		sub.State = "active"
	}
	if sub.Keys.Primary == "" {
		sub.Keys.Primary = "sub-" + id + "-primary"
	}
	if sub.Keys.Secondary == "" {
		sub.Keys.Secondary = "sub-" + id + "-secondary"
	}
	s.mu.Lock()
	s.cfg.Subscriptions.Items = cloneSubscriptions(s.cfg.Subscriptions.Items)
	s.cfg.Subscriptions.Items[id] = sub
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, sub)
}

func (s *server) deleteSubscription(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	s.mu.Lock()
	if _, ok := s.cfg.Subscriptions.Items[id]; !ok {
		s.mu.Unlock()
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Subscription not found"})
		return
	}
	s.cfg.Subscriptions.Items = cloneSubscriptions(s.cfg.Subscriptions.Items)
	delete(s.cfg.Subscriptions.Items, id)
	s.mu.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) listNamedValues(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"items": namedValueSummaries(s.cfg.NamedValues)})
}

func (s *server) upsertNamedValue(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		ID string `json:"id"`
		NamedValueConfig
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid named value payload"})
		return
	}
	id := firstString(r.PathValue("id"), payload.ID)
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Named value id is required"})
		return
	}
	s.mu.Lock()
	s.cfg.NamedValues = cloneMap(s.cfg.NamedValues)
	s.cfg.NamedValues[id] = payload.NamedValueConfig
	namedValue := s.cfg.NamedValues[id]
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]any{"id": id, "named_value": namedValue})
}

func (s *server) deleteNamedValue(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	s.mu.Lock()
	if _, ok := s.cfg.NamedValues[id]; !ok {
		s.mu.Unlock()
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Named value not found"})
		return
	}
	s.cfg.NamedValues = cloneMap(s.cfg.NamedValues)
	delete(s.cfg.NamedValues, id)
	s.mu.Unlock()
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) listTraces(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"items": s.traces.list()})
}

type replayRequest struct {
	Method  string            `json:"method"`
	Path    string            `json:"path"`
	Headers map[string]string `json:"headers"`
	Body    string            `json:"body_text"`
}

func (s *server) replay(w http.ResponseWriter, r *http.Request) {
	var req replayRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid replay request"})
		return
	}
	method := strings.ToUpper(firstString(req.Method, http.MethodGet))
	replayPath := firstString(req.Path, "/")
	proxyReq, err := http.NewRequestWithContext(r.Context(), method, replayPath, bytes.NewBufferString(req.Body))
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid replay path"})
		return
	}
	proxyReq.Host = r.Host
	for key, value := range req.Headers {
		proxyReq.Header.Set(key, value)
	}
	rec := &captureResponse{header: http.Header{}}
	s.dispatch(rec, proxyReq)
	traceItems := s.traces.list()
	var trace any
	if len(traceItems) > 0 {
		trace = traceItems[0]
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"response": dumpResponse(rec.statusCode(), rec.header, rec.body.Bytes()),
		"trace":    trace,
	})
}

func (s *server) getPolicy(w http.ResponseWriter, r *http.Request) {
	key := policyKey(r.PathValue("scope"), r.PathValue("name"))
	s.mu.RLock()
	xml := s.policies[key]
	s.mu.RUnlock()
	if xml == "" {
		xml = "<policies><inbound /><backend /><outbound /><on-error /></policies>"
	}
	writeJSON(w, http.StatusOK, map[string]string{"scope_type": r.PathValue("scope"), "scope_name": r.PathValue("name"), "xml": xml})
}

func (s *server) putPolicy(w http.ResponseWriter, r *http.Request) {
	var payload struct {
		XML string `json:"xml"`
	}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid policy payload"})
		return
	}
	key := policyKey(r.PathValue("scope"), r.PathValue("name"))
	s.mu.Lock()
	s.policies[key] = payload.XML
	s.mu.Unlock()
	writeJSON(w, http.StatusOK, map[string]string{"status": "saved"})
}

func (s *server) rotateSubscriptionKey(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	which := r.URL.Query().Get("key")
	if which == "" {
		which = "primary"
	}
	s.cfg.Subscriptions.Items = cloneSubscriptions(s.cfg.Subscriptions.Items)
	for name, sub := range s.cfg.Subscriptions.Items {
		if sub.ID != id && name != id {
			continue
		}
		if strings.EqualFold(which, "secondary") {
			sub.Keys.Secondary = "rotated-secondary-" + newTraceID()[:8]
		} else {
			sub.Keys.Primary = "rotated-primary-" + newTraceID()[:8]
		}
		s.cfg.Subscriptions.Items[name] = sub
		writeJSON(w, http.StatusOK, sub)
		return
	}
	writeJSON(w, http.StatusNotFound, map[string]string{"error": "Subscription not found"})
}

type captureResponse struct {
	header http.Header
	body   bytes.Buffer
	status int
}

func (c *captureResponse) Header() http.Header { return c.header }

func (c *captureResponse) WriteHeader(status int) { c.status = status }

func (c *captureResponse) Write(data []byte) (int, error) {
	if c.status == 0 {
		c.status = http.StatusOK
	}
	return c.body.Write(data)
}

func (c *captureResponse) statusCode() int {
	if c.status == 0 {
		return http.StatusOK
	}
	return c.status
}

func apiSummaries(apis map[string]APIConfig) []map[string]any {
	keys := sortedKeys(apis)
	out := make([]map[string]any, 0, len(keys))
	for _, key := range keys {
		api := apis[key]
		out = append(out, map[string]any{
			"id": key, "name": firstString(api.Name, key), "path": api.Path,
			"type": firstString(api.Type, "http"), "products": api.Products, "mcp_properties": api.MCPProperties,
		})
	}
	return out
}

func routeSummaries(routes []RouteConfig) []map[string]any {
	out := make([]map[string]any, 0, len(routes))
	for _, route := range routes {
		out = append(out, map[string]any{
			"name": route.Name, "path_prefix": route.PathPrefix, "host_match": route.HostMatch,
			"upstream_base_url": route.UpstreamBaseURL, "upstream_path_prefix": route.UpstreamPathPrefix,
			"product": route.Product,
		})
	}
	return out
}

func productSummaries(products map[string]ProductConfig) []map[string]any {
	keys := sortedKeys(products)
	out := make([]map[string]any, 0, len(keys))
	for _, key := range keys {
		product := products[key]
		out = append(out, map[string]any{
			"id": key, "name": firstString(product.Name, key), "description": product.Description,
			"require_subscription": product.RequireSubscription, "groups": product.Groups, "tags": product.Tags,
		})
	}
	return out
}

func namedValueSummaries(namedValues map[string]NamedValueConfig) []map[string]any {
	keys := sortedKeys(namedValues)
	out := make([]map[string]any, 0, len(keys))
	for _, key := range keys {
		namedValue := namedValues[key]
		value := namedValue.Value
		if namedValue.Secret && value != "" {
			value = "***"
		}
		out = append(out, map[string]any{"id": key, "value": value, "secret": namedValue.Secret})
	}
	return out
}

func subscriptionSummaries(items map[string]Subscription) []Subscription {
	keys := sortedKeys(items)
	out := make([]Subscription, 0, len(keys))
	for _, key := range keys {
		out = append(out, items[key])
	}
	return out
}

func backendSummaries(cfg Config) []map[string]any {
	out := []map[string]any{}
	for key, backend := range cfg.Backends {
		out = append(out, map[string]any{"id": key, "url": backend.URL})
	}
	for _, route := range cfg.Routes {
		out = append(out, map[string]any{"id": route.Name, "url": route.UpstreamBaseURL})
	}
	return out
}

func policyScopes(cfg Config) []map[string]string {
	scopes := []map[string]string{{"scope_type": "gateway", "scope_name": "global"}}
	for key := range cfg.APIs {
		scopes = append(scopes, map[string]string{"scope_type": "api", "scope_name": key})
	}
	for _, route := range cfg.Routes {
		scopes = append(scopes, map[string]string{"scope_type": "route", "scope_name": route.Name})
	}
	return scopes
}

func policyKey(scope, name string) string {
	return scope + "/" + name
}

func cloneSubscriptions(input map[string]Subscription) map[string]Subscription {
	out := make(map[string]Subscription, len(input))
	for key, value := range input {
		out[key] = value
	}
	return out
}

func cloneMap[V any](input map[string]V) map[string]V {
	out := make(map[string]V, len(input))
	for key, value := range input {
		out[key] = value
	}
	return out
}

func routesFromAPIsWithExplicit(apis map[string]APIConfig, routes []RouteConfig) []RouteConfig {
	explicit := make([]RouteConfig, 0, len(routes))
	for _, route := range routes {
		if route.Metadata["api_id"] == "" {
			explicit = append(explicit, route)
		}
	}
	return append(explicit, routesFromAPIs(apis)...)
}

func unlinkProduct(subscriptions map[string]Subscription, apis map[string]APIConfig, routes []RouteConfig, id string) {
	for key, sub := range subscriptions {
		sub.Products = removeString(sub.Products, id)
		subscriptions[key] = sub
	}
	for key, api := range apis {
		api.Products = removeString(api.Products, id)
		apis[key] = api
	}
	for index := range routes {
		if routes[index].Product == id {
			routes[index].Product = ""
		}
	}
}

func removeString(values []string, item string) []string {
	out := values[:0]
	for _, value := range values {
		if value != item {
			out = append(out, value)
		}
	}
	return out
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for key := range m {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

var _ io.Writer = (*captureResponse)(nil)
