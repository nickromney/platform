package workflow

import (
	"fmt"
	"sort"
	"strings"
)

type Plan struct {
	DryRun    bool     `json:"dry_run"`
	Runtime   string   `json:"runtime"`
	Summary   string   `json:"summary"`
	Commands  []string `json:"commands"`
	Manifests []string `json:"manifests"`
}

type EnvironmentRequest struct {
	App         string
	Environment string
	Action      string
}

type DeploymentRequest struct {
	App         string
	Environment string
	Image       string
}

type SecretRequest struct {
	App         string
	Environment string
	Secret      string
	Keys        []string
}

type Adapter interface {
	Name() string
	Description() string
	PlanEnvironment(req EnvironmentRequest) *Plan
	PlanDeployment(req DeploymentRequest) *Plan
	PlanSecret(req SecretRequest) *Plan
}

type Registry struct {
	adapters map[string]Adapter
}

func NewRegistry() *Registry {
	return &Registry{adapters: make(map[string]Adapter)}
}

func NewPlatformRuntimeRegistry() *Registry {
	registry := NewRegistry()
	registry.Register(&GenericAdapter{})
	registry.Register(NewMakeAdapter("kind", "Local kind workflow adapter", "kubernetes/kind", "kind"))
	registry.Register(NewMakeAdapter("lima", "Local Lima workflow adapter", "kubernetes/lima", "lima"))
	registry.Register(NewMakeAdapter("slicer", "Local Slicer workflow adapter", "kubernetes/slicer", "slicer"))
	return registry
}

func (r *Registry) Register(a Adapter) {
	r.adapters[a.Name()] = a
}

func (r *Registry) Get(name string) (Adapter, bool) {
	a, ok := r.adapters[name]
	return a, ok
}

func (r *Registry) List() []Adapter {
	names := make([]string, 0, len(r.adapters))
	for name := range r.adapters {
		names = append(names, name)
	}
	sort.Strings(names)

	list := make([]Adapter, 0, len(names))
	for _, name := range names {
		list = append(list, r.adapters[name])
	}
	return list
}

func NewPlan(runtime, summary string, commands, manifests []string) *Plan {
	return &Plan{
		DryRun:    true,
		Runtime:   runtime,
		Summary:   summary,
		Commands:  commands,
		Manifests: manifests,
	}
}

// GenericAdapter implements a generic Kubernetes workflow.
type GenericAdapter struct{}

func (g *GenericAdapter) Name() string        { return "generic_kubernetes" }
func (g *GenericAdapter) Description() string { return "Generic Kubernetes workflow adapter" }

func (g *GenericAdapter) PlanEnvironment(req EnvironmentRequest) *Plan {
	namespace := req.App + "-" + req.Environment
	verb := "create namespace"
	if req.Action != "create" {
		verb = "delete namespace"
	}
	return NewPlan(g.Name(),
		fmt.Sprintf("would %s environment %s for %s on generic Kubernetes", req.Action, req.Environment, req.App),
		[]string{fmt.Sprintf("kubectl %s %s --dry-run=client -o yaml", verb, namespace)},
		[]string{"Namespace/" + namespace},
	)
}

func (g *GenericAdapter) PlanDeployment(req DeploymentRequest) *Plan {
	namespace := req.App + "-" + req.Environment
	return NewPlan(g.Name(),
		fmt.Sprintf("would deploy %s to %s/%s on generic Kubernetes", req.Image, req.App, req.Environment),
		[]string{fmt.Sprintf("kubectl set image deployment/%s %s=%s --namespace %s --dry-run=server", req.App, req.App, req.Image, namespace)},
		[]string{fmt.Sprintf("Deployment/%s/%s", namespace, req.App)},
	)
}

func (g *GenericAdapter) PlanSecret(req SecretRequest) *Plan {
	namespace := req.App + "-" + req.Environment
	var literals []string
	for _, key := range req.Keys {
		literals = append(literals, "--from-literal="+key+"=<redacted>")
	}
	return NewPlan(g.Name(),
		fmt.Sprintf("would reconcile secret %s for %s/%s on generic Kubernetes", req.Secret, req.App, req.Environment),
		[]string{fmt.Sprintf("kubectl create secret generic %s --namespace %s %s --dry-run=client -o yaml", req.Secret, namespace, strings.Join(literals, " "))},
		[]string{fmt.Sprintf("Secret/%s/%s", namespace, req.Secret)},
	)
}

// MakeAdapter implements a Make-based workflow.
type MakeAdapter struct {
	name        string
	description string
	makeDir     string
	displayName string
}

func NewMakeAdapter(name, description, makeDir, displayName string) *MakeAdapter {
	return &MakeAdapter{
		name:        name,
		description: description,
		makeDir:     makeDir,
		displayName: displayName,
	}
}

func (m *MakeAdapter) Name() string        { return m.name }
func (m *MakeAdapter) Description() string { return m.description }

func (m *MakeAdapter) PlanEnvironment(req EnvironmentRequest) *Plan {
	return NewPlan(m.name,
		fmt.Sprintf("would %s environment %s for %s on %s", req.Action, req.Environment, req.App, m.displayName),
		[]string{fmt.Sprintf("make -C %s idp-env ACTION=%s APP=%s ENV=%s DRY_RUN=1", m.makeDir, req.Action, req.App, req.Environment)},
		[]string{fmt.Sprintf("EnvironmentRequest/%s/%s", req.App, req.Environment)},
	)
}

func (m *MakeAdapter) PlanDeployment(req DeploymentRequest) *Plan {
	return NewPlan(m.name,
		fmt.Sprintf("would deploy %s to %s/%s on %s", req.Image, req.App, req.Environment, m.displayName),
		[]string{fmt.Sprintf("make -C %s idp-deployments APP=%s ENV=%s IMAGE=%s DRY_RUN=1", m.makeDir, req.App, req.Environment, req.Image)},
		[]string{fmt.Sprintf("Deployment/%s/%s", req.App, req.Environment)},
	)
}

func (m *MakeAdapter) PlanSecret(req SecretRequest) *Plan {
	return NewPlan(m.name,
		fmt.Sprintf("would reconcile secret %s for %s/%s on %s", req.Secret, req.App, req.Environment, m.displayName),
		[]string{fmt.Sprintf("make -C %s idp-secrets APP=%s ENV=%s SECRET=%s KEYS=%s DRY_RUN=1", m.makeDir, req.App, req.Environment, req.Secret, strings.Join(req.Keys, ","))},
		[]string{fmt.Sprintf("Secret/%s/%s/%s", req.App, req.Environment, req.Secret)},
	)
}
