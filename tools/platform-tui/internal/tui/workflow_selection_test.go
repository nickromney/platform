package tui

import (
	"reflect"
	"testing"
)

func TestWorkflowSelectionBuildsPreviewArgs(t *testing.T) {
	selection := WorkflowSelection{
		Options: workflowOptions{
			Stages: []stageOption{
				{ID: "900", Label: "sso", AppToggles: true},
			},
			ActionMetadata: []actionOption{
				{ID: "apply", Label: "apply", UsesAutoApprove: true, SupportsAppToggles: true},
			},
			Apps: []string{"sentiment", "subnetcalc"},
			Presets: []presetOption{
				{
					ID:    "minimal",
					Group: "app_set",
					Overlay: map[string]interface{}{
						"enable_app_repo_sentiment":  false,
						"enable_app_repo_subnetcalc": true,
					},
				},
			},
		},
		Variant:               "kind",
		Stage:                 "900",
		Action:                "apply",
		PresetResourceProfile: "local-idp-12gb",
		PresetAppSet:          "minimal",
		CustomWorkerCount:     "2",
		AppOverrides: map[string]string{
			"sentiment":  "sentiment=off",
			"subnetcalc": "subnetcalc=off",
		},
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
	if got := selection.WorkflowArgs("preview"); !reflect.DeepEqual(got, want) {
		t.Fatalf("preview args\nwant %#v\n got %#v", want, got)
	}
}

func TestWorkflowSelectionSkipsAppOverridesBeforeAppToggleStage(t *testing.T) {
	selection := WorkflowSelection{
		Options: workflowOptions{
			Stages: []stageOption{
				{ID: "100", Label: "cluster"},
			},
			ActionMetadata: []actionOption{
				{ID: "plan", Label: "plan", SupportsAppToggles: true},
			},
			Apps: []string{"sentiment"},
		},
		Variant: "kind",
		Stage:   "100",
		Action:  "plan",
		AppOverrides: map[string]string{
			"sentiment": "sentiment=on",
		},
	}

	got := selection.WorkflowArgs("preview")
	if contains(got, "--app") {
		t.Fatalf("stage without app toggles should not emit app overrides: %#v", got)
	}
}
