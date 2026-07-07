package workflow

import "testing"

func TestNewPlatformRuntimeRegistryListsDeterministicRuntimeAdapters(t *testing.T) {
	registry := NewPlatformRuntimeRegistry()

	var names []string
	for _, adapter := range registry.List() {
		names = append(names, adapter.Name())
	}

	want := []string{"generic_kubernetes", "kind", "lima"}
	if len(names) != len(want) {
		t.Fatalf("runtime adapters = %#v, want %#v", names, want)
	}
	for i := range want {
		if names[i] != want[i] {
			t.Fatalf("runtime adapters = %#v, want %#v", names, want)
		}
	}
}
