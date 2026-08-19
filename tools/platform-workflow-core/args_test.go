package workflowcore

import (
	"reflect"
	"testing"
)

func testOptions() Options {
	return Options{
		Stages: []StageOption{
			{ID: "900", AppToggles: true},
		},
		ActionMetadata: []ActionOption{
			{ID: "apply", UsesAutoApprove: true, SupportsAppToggles: true},
		},
		Apps: []string{"sentiment", "subnetcalc"},
		Presets: []PresetOption{
			{
				ID:    "minimal",
				Group: "app_set",
				Overlay: map[string]any{
					"enable_app_repo_sentiment":  false,
					"enable_app_repo_subnetcalc": true,
				},
			},
		},
	}
}

func TestArgsPreviewMatchesTUIContract(t *testing.T) {
	sel := Selection{
		Variant: "kind",
		Stage:   "900",
		Action:  "apply",
		Presets: map[string]string{
			"resource-profile": "local-idp-12gb",
			"app-set":          "minimal",
		},
		Sets: map[string]string{"worker_count": "2"},
		Apps: map[string]string{
			"sentiment":  "sentiment=off",
			"subnetcalc": "subnetcalc=off",
		},
		AutoApprove: true,
	}

	want := []string{
		"preview", "--execute", "--output", "json",
		"--variant", "kind",
		"--stage", "900",
		"--action", "apply",
		"--preset", "resource-profile=local-idp-12gb",
		"--preset", "app-set=minimal",
		"--set", "worker_count=2",
		"--app", "subnetcalc=off",
		"--auto-approve",
	}
	got := Args(testOptions(), sel, "preview", "--execute")
	got = append(got[:2], append([]string{"--output", "json"}, got[2:]...)...)
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("preview args\nwant %#v\n got %#v", want, got)
	}
}

func TestHiddenFromActionDropdown(t *testing.T) {
	if !HiddenFromActionDropdown("reset") || !HiddenFromActionDropdown("state-reset") {
		t.Fatal("reset and state-reset must stay out of the action dropdown")
	}
	if HiddenFromActionDropdown("apply") {
		t.Fatal("apply must remain in the action dropdown")
	}
}

func TestActionUsesAutoApproveFallback(t *testing.T) {
	if !ActionUsesAutoApprove(Options{}, "state-reset") {
		t.Fatal("state-reset uses auto-approve")
	}
	if ActionUsesAutoApprove(Options{}, "plan") {
		t.Fatal("plan does not use auto-approve")
	}
}
