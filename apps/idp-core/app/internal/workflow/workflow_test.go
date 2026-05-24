package workflow

import "testing"

func TestNewPlatformRuntimeRegistryListsDeterministicRuntimeAdapters(t *testing.T) {
	registry := NewPlatformRuntimeRegistry()

	var names []string
	for _, adapter := range registry.List() {
		names = append(names, adapter.Name())
	}

	want := []string{"generic_kubernetes", "kind", "lima", "slicer"}
	if len(names) != len(want) {
		t.Fatalf("runtime adapters = %#v, want %#v", names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Fatalf("runtime adapters = %#v, want %#v", names, want)
		}
	}
}

func TestPlatformRuntimeRegistryProvidesSlicerAdapter(t *testing.T) {
	registry := NewPlatformRuntimeRegistry()

	adapter, ok := registry.Get("slicer")
	if !ok {
		t.Fatal("slicer adapter missing")
	}

	plan := adapter.PlanEnvironment(EnvironmentRequest{
		App:         "hello-platform",
		Environment: "preview",
		Action:      "create",
	})
	if plan.Runtime != "slicer" {
		t.Fatalf("plan runtime = %q, want slicer", plan.Runtime)
	}
	if len(plan.Commands) != 1 || plan.Commands[0] != "make -C kubernetes/slicer idp-env ACTION=create APP=hello-platform ENV=preview DRY_RUN=1" {
		t.Fatalf("plan commands = %#v", plan.Commands)
	}
}
