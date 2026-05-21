package app

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
)

type Config struct {
	Addr                string                      `json:"-"`
	AllowedOrigins      []string                    `json:"allowed_origins"`
	AllowAnonymous      bool                        `json:"allow_anonymous"`
	TraceEnabled        bool                        `json:"trace_enabled"`
	ProxyTimeoutSeconds int                         `json:"proxy_timeout_seconds"`
	OIDC                OIDCConfig                  `json:"oidc"`
	TenantAccess        TenantAccessConfig          `json:"tenant_access"`
	Subscriptions       SubscriptionConfig          `json:"subscription"`
	Products            map[string]ProductConfig    `json:"products"`
	NamedValues         map[string]NamedValueConfig `json:"named_values"`
	APIs                map[string]APIConfig        `json:"apis"`
	Routes              []RouteConfig               `json:"routes"`
	Policies            map[string]ScopedPolicy     `json:"policies"`
	Backends            map[string]BackendConfig    `json:"backends"`
	Raw                 map[string]json.RawMessage  `json:"-"`
}

type OIDCConfig struct {
	Issuer   string `json:"issuer"`
	Audience string `json:"audience"`
	JWKSURI  string `json:"jwks_uri"`
}

type TenantAccessConfig struct {
	Enabled      bool   `json:"enabled"`
	PrimaryKey   string `json:"primary_key"`
	SecondaryKey string `json:"secondary_key"`
}

type ProductConfig struct {
	Name                string   `json:"name"`
	Description         string   `json:"description"`
	RequireSubscription bool     `json:"require_subscription"`
	Groups              []string `json:"groups,omitempty"`
	Tags                []string `json:"tags,omitempty"`
}

type NamedValueConfig struct {
	Value  string `json:"value"`
	Secret bool   `json:"secret"`
}

type APIConfig struct {
	Name               string                     `json:"name"`
	Path               string                     `json:"path"`
	UpstreamBaseURL    string                     `json:"upstream_base_url"`
	UpstreamPathPrefix string                     `json:"upstream_path_prefix"`
	Type               string                     `json:"type"`
	MCPProperties      *MCPPropertiesConfig       `json:"mcp_properties,omitempty"`
	Products           []string                   `json:"products"`
	Operations         map[string]OperationConfig `json:"operations"`
	PoliciesXML        string                     `json:"policies_xml"`
}

func (a *APIConfig) UnmarshalJSON(data []byte) error {
	type apiConfig APIConfig
	var aux struct {
		*apiConfig
		MCPPropertiesCamel *MCPPropertiesConfig `json:"mcpProperties"`
	}
	aux.apiConfig = (*apiConfig)(a)
	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}
	if a.MCPProperties == nil && aux.MCPPropertiesCamel != nil {
		a.MCPProperties = aux.MCPPropertiesCamel
	}
	return nil
}

type MCPPropertiesConfig struct {
	TransportType string              `json:"transport_type"`
	Endpoints     []MCPEndpointConfig `json:"endpoints"`
}

func (m *MCPPropertiesConfig) UnmarshalJSON(data []byte) error {
	type mcpPropertiesConfig MCPPropertiesConfig
	var aux struct {
		*mcpPropertiesConfig
		TransportTypeCamel string `json:"transportType"`
	}
	aux.mcpPropertiesConfig = (*mcpPropertiesConfig)(m)
	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}
	if m.TransportType == "" {
		m.TransportType = aux.TransportTypeCamel
	}
	return nil
}

type MCPEndpointConfig struct {
	Name        string `json:"name"`
	URITemplate string `json:"uri_template"`
}

func (e *MCPEndpointConfig) UnmarshalJSON(data []byte) error {
	type mcpEndpointConfig MCPEndpointConfig
	var aux struct {
		*mcpEndpointConfig
		URITemplateCamel string `json:"uriTemplate"`
	}
	aux.mcpEndpointConfig = (*mcpEndpointConfig)(e)
	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}
	if e.URITemplate == "" {
		e.URITemplate = aux.URITemplateCamel
	}
	return nil
}

type OperationConfig struct {
	Name        string `json:"name"`
	Method      string `json:"method"`
	URLTemplate string `json:"url_template"`
	PoliciesXML string `json:"policies_xml"`
}

type BackendConfig struct {
	URL string `json:"url"`
}

type RouteConfig struct {
	Name               string            `json:"name"`
	HostMatch          []string          `json:"host_match"`
	PathPrefix         string            `json:"path_prefix"`
	UpstreamBaseURL    string            `json:"upstream_base_url"`
	UpstreamPathPrefix string            `json:"upstream_path_prefix"`
	Product            string            `json:"product"`
	AllowAnonymous     bool              `json:"allow_anonymous"`
	Authz              RouteAuthzConfig  `json:"authz"`
	PoliciesXML        string            `json:"policies_xml"`
	Metadata           map[string]string `json:"metadata,omitempty"`
}

type RouteAuthzConfig struct {
	RequiredRoles  []string          `json:"required_roles"`
	RequiredGroups []string          `json:"required_groups"`
	RequiredClaims map[string]string `json:"required_claims"`
}

type SubscriptionConfig struct {
	Required        bool                       `json:"required"`
	HeaderNames     []string                   `json:"header_names"`
	QueryParamNames []string                   `json:"query_param_names"`
	Items           map[string]Subscription    `json:"subscriptions"`
	LegacyKeys      map[string]SubscriptionRef `json:"keys"`
	Bypass          []HeaderCondition          `json:"bypass"`
}

type SubscriptionRef struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type Subscription struct {
	ID        string           `json:"id"`
	Name      string           `json:"name"`
	Keys      SubscriptionKeys `json:"keys"`
	State     string           `json:"state"`
	Products  []string         `json:"products"`
	CreatedBy string           `json:"created_by"`
}

type SubscriptionKeys struct {
	Primary   string `json:"primary"`
	Secondary string `json:"secondary"`
}

type HeaderCondition struct {
	Header     string `json:"header"`
	StartsWith string `json:"starts_with"`
	Equals     string `json:"equals"`
}

type ScopedPolicy struct {
	XML string `json:"xml"`
}

func LoadConfig(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, err
	}
	if strings.EqualFold(os.Getenv("APIM_CONFIG_TEMPLATE_SUBSTITUTE"), "true") {
		data = []byte(substituteEnv(string(data)))
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, err
	}
	_ = json.Unmarshal(data, &cfg.Raw)
	cfg.applyDefaults()
	return cfg, nil
}

func (c *Config) applyDefaults() {
	if c.Addr == "" {
		c.Addr = ":8000"
	}
	if c.ProxyTimeoutSeconds == 0 {
		c.ProxyTimeoutSeconds = 60
	}
	if c.Products == nil {
		c.Products = map[string]ProductConfig{}
	}
	if c.NamedValues == nil {
		c.NamedValues = map[string]NamedValueConfig{}
	}
	if c.APIs == nil {
		c.APIs = map[string]APIConfig{}
	}
	if c.Backends == nil {
		c.Backends = map[string]BackendConfig{}
	}
	if c.Policies == nil {
		c.Policies = map[string]ScopedPolicy{}
	}
	if len(c.Subscriptions.HeaderNames) == 0 {
		c.Subscriptions.HeaderNames = []string{"Ocp-Apim-Subscription-Key", "X-Ocp-Apim-Subscription-Key"}
	}
	if len(c.Subscriptions.QueryParamNames) == 0 {
		c.Subscriptions.QueryParamNames = []string{"subscription-key"}
	}
	if c.Subscriptions.Items == nil {
		c.Subscriptions.Items = map[string]Subscription{}
	}
	if c.Subscriptions.LegacyKeys == nil {
		c.Subscriptions.LegacyKeys = map[string]SubscriptionRef{}
	}
	if len(c.Routes) == 0 {
		c.Routes = routesFromAPIs(c.APIs)
	}
}

func (c *Config) ApplyRuntimeDefaults() {
	c.applyDefaults()
}

func routesFromAPIs(apis map[string]APIConfig) []RouteConfig {
	routes := make([]RouteConfig, 0, len(apis))
	for id, api := range apis {
		prefix := "/" + strings.Trim(api.Path, "/")
		if prefix == "/" {
			prefix = ""
		}
		product := ""
		if len(api.Products) > 0 {
			product = api.Products[0]
		}
		if api.MCPProperties != nil && len(api.MCPProperties.Endpoints) > 0 {
			for _, endpoint := range api.MCPProperties.Endpoints {
				endpointPrefix := "/" + strings.Trim(endpoint.URITemplate, "/")
				if endpointPrefix == "/" {
					endpointPrefix = ""
				}
				routes = append(routes, RouteConfig{
					Name:               firstString(api.Name, id) + ":" + firstString(endpoint.Name, "endpoint"),
					PathPrefix:         joinURLPath(prefix, endpointPrefix),
					UpstreamBaseURL:    api.UpstreamBaseURL,
					UpstreamPathPrefix: joinURLPath(api.UpstreamPathPrefix, endpointPrefix),
					Product:            product,
					PoliciesXML:        api.PoliciesXML,
					Metadata:           map[string]string{"api_id": id, "api_type": firstString(api.Type, "mcp"), "mcp_transport": api.MCPProperties.TransportType},
				})
			}
			continue
		}
		routes = append(routes, RouteConfig{
			Name:               firstString(api.Name, id),
			PathPrefix:         prefix,
			UpstreamBaseURL:    api.UpstreamBaseURL,
			UpstreamPathPrefix: firstString(api.UpstreamPathPrefix, prefix),
			Product:            product,
			PoliciesXML:        api.PoliciesXML,
			Metadata:           map[string]string{"api_id": id, "api_type": api.Type},
		})
	}
	return routes
}

func joinURLPath(parts ...string) string {
	out := ""
	for _, part := range parts {
		part = strings.Trim(part, "/")
		if part == "" {
			continue
		}
		out += "/" + part
	}
	if out == "" {
		return ""
	}
	return out
}

var envPattern = regexp.MustCompile(`\$\{([A-Za-z_][A-Za-z0-9_]*)(:-([^}]*))?}`)

func substituteEnv(input string) string {
	return envPattern.ReplaceAllStringFunc(input, func(match string) string {
		parts := envPattern.FindStringSubmatch(match)
		if len(parts) == 0 {
			return match
		}
		if value := os.Getenv(parts[1]); value != "" {
			return value
		}
		if len(parts) > 3 {
			return parts[3]
		}
		return ""
	})
}

func (c Config) validate() error {
	for _, route := range c.Routes {
		if route.Name == "" || route.UpstreamBaseURL == "" {
			return fmt.Errorf("route name and upstream_base_url are required")
		}
	}
	return nil
}

func firstString(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func splitHeaderValues(values []string) []string {
	seen := map[string]bool{}
	result := []string{}
	for _, value := range values {
		for _, part := range strings.Split(value, ",") {
			trimmed := strings.TrimSpace(part)
			if trimmed == "" || seen[trimmed] {
				continue
			}
			seen[trimmed] = true
			result = append(result, trimmed)
		}
	}
	return result
}
