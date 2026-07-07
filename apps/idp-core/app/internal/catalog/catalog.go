package catalog

import (
	"encoding/json"
	"fmt"
	"os"
)

type Catalog struct {
	SchemaVersion  string            `json:"schema_version"`
	CoreComponents map[string]string `json:"core_components"`
	Applications   []Application     `json:"applications"`
}

type Application struct {
	Name         string        `json:"name"`
	DisplayName  string        `json:"display_name"`
	Owner        string        `json:"owner"`
	Lifecycle    string        `json:"lifecycle"`
	Source       Source        `json:"source"`
	Deployment   Deployment    `json:"deployment"`
	Environments []Environment `json:"environments"`
	Secrets      []Secret      `json:"secrets"`
	Scorecard    Scorecard     `json:"scorecard"`
	Health       string        `json:"health,omitempty"`
}

type Source struct {
	Repo string `json:"repo"`
	Path string `json:"path"`
}

type Deployment struct {
	Strategy     string   `json:"strategy"`
	Controller   string   `json:"controller"`
	Applications []string `json:"applications"`
	Image        string   `json:"image,omitempty"`
	Sync         string   `json:"sync,omitempty"`
}

type Environment struct {
	Name       string      `json:"name"`
	Type       string      `json:"type"`
	Namespace  string      `json:"namespace"`
	Route      string      `json:"route"`
	RBAC       RBAC        `json:"rbac"`
	Deployment *Deployment `json:"deployment,omitempty"`
	Health     string      `json:"health,omitempty"`
	Sync       string      `json:"sync,omitempty"`
}

type RBAC struct {
	Group   string `json:"group"`
	Viewer  bool   `json:"viewer"`
	Mutator bool   `json:"mutator"`
}

type Secret struct {
	Name     string `json:"name"`
	Binding  string `json:"binding"`
	Rotation string `json:"rotation"`
	Scope    string `json:"scope,omitempty"`
}

type Scorecard struct {
	RuntimeProfile            string `json:"runtime_profile"`
	HasHealthEndpoint         bool   `json:"has_health_endpoint"`
	HasNetworkPolicy          bool   `json:"has_network_policy"`
	HasRuntimeProbes          bool   `json:"has_runtime_probes"`
	HasResourceRequestsLimits bool   `json:"has_resource_requests_limits"`
	HasOwner                  bool   `json:"has_owner"`
	HasModelCard              bool   `json:"has_model_card,omitempty"`
	Tier                      string `json:"tier,omitempty"`
}

func Load(path string) (*Catalog, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read catalog file: %w", err)
	}
	var c Catalog
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, fmt.Errorf("unmarshal catalog: %w", err)
	}
	return &c, nil
}

func (c *Catalog) GetApp(name string) (*Application, bool) {
	for _, app := range c.Applications {
		if app.Name == name {
			return &app, true
		}
	}
	return nil, false
}

type DeploymentRecord struct {
	App         string `json:"app"`
	Environment string `json:"environment"`
	Route       any    `json:"route"`
	Controller  string `json:"controller"`
	Image       string `json:"image"`
	Health      string `json:"health"`
	Sync        string `json:"sync"`
}

func (c *Catalog) ListDeployments() []DeploymentRecord {
	var records []DeploymentRecord
	for _, app := range c.Applications {
		for _, env := range app.Environments {
			image := app.Deployment.Image
			if env.Deployment != nil && env.Deployment.Image != "" {
				image = env.Deployment.Image
			}

			health := app.Health
			if env.Health != "" {
				health = env.Health
			}

			sync := app.Deployment.Sync
			if env.Sync != "" {
				sync = env.Sync
			}

			var route any = env.Route
			if env.Route == "" {
				route = nil
			}

			records = append(records, DeploymentRecord{
				App:         app.Name,
				Environment: env.Name,
				Route:       route,
				Controller:  app.Deployment.Controller,
				Image:       image,
				Health:      health,
				Sync:        sync,
			})
		}
	}
	return records
}

type SecretRecord struct {
	Name     string `json:"name"`
	Binding  string `json:"binding"`
	Rotation string `json:"rotation"`
	App      string `json:"app"`
	Scope    string `json:"scope,omitempty"`
}

func (c *Catalog) ListSecrets() []SecretRecord {
	var records []SecretRecord
	for _, app := range c.Applications {
		for _, s := range app.Secrets {
			binding := s.Binding
			if binding == "" {
				binding = "not declared"
			}
			rotation := s.Rotation
			if rotation == "" {
				rotation = "not declared"
			}
			records = append(records, SecretRecord{
				Name:     s.Name,
				Binding:  binding,
				Rotation: rotation,
				App:      app.Name,
				Scope:    s.Scope,
			})
		}
	}
	return records
}

type ScorecardRecord struct {
	App                       string `json:"app"`
	RuntimeProfile            string `json:"runtime_profile"`
	HasHealthEndpoint         bool   `json:"has_health_endpoint"`
	HasNetworkPolicy          bool   `json:"has_network_policy"`
	HasRuntimeProbes          bool   `json:"has_runtime_probes"`
	HasResourceRequestsLimits bool   `json:"has_resource_requests_limits"`
	HasOwner                  bool   `json:"has_owner"`
	HasModelCard              *bool  `json:"has_model_card,omitempty"`
	Tier                      string `json:"tier,omitempty"`
}

func (c *Catalog) ListScorecards() []ScorecardRecord {
	var records []ScorecardRecord
	for _, app := range c.Applications {
		profile := app.Scorecard.RuntimeProfile
		if profile == "" {
			profile = "not declared"
		}

		hasOwner := app.Scorecard.HasOwner
		if app.Owner != "" {
			hasOwner = true
		}

		record := ScorecardRecord{
			App:                       app.Name,
			RuntimeProfile:            profile,
			HasHealthEndpoint:         app.Scorecard.HasHealthEndpoint,
			HasNetworkPolicy:          app.Scorecard.HasNetworkPolicy,
			HasRuntimeProbes:          app.Scorecard.HasRuntimeProbes,
			HasResourceRequestsLimits: app.Scorecard.HasResourceRequestsLimits,
			HasOwner:                  hasOwner,
			Tier:                      app.Scorecard.Tier,
		}

		// Optional field
		if app.Scorecard.HasModelCard {
			val := true
			record.HasModelCard = &val
		}

		records = append(records, record)
	}
	return records
}
