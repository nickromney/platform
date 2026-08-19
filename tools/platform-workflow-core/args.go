package workflowcore

import "strings"

type ActionOption struct {
	ID                 string
	UsesAutoApprove    bool
	SupportsAppToggles bool
}

type StageOption struct {
	ID         string
	AppToggles bool
}

type PresetOption struct {
	Group   string
	ID      string
	Overlay map[string]any
}

type UIRules struct {
	AppToggleStages  []string
	AppToggleActions []string
}

type Options struct {
	Stages         []StageOption
	ActionMetadata []ActionOption
	Apps           []string
	Presets        []PresetOption
	UIRules        UIRules
}

type Selection struct {
	Variant string
	Stage   string
	Action  string
	// Presets is group-id -> value. Empty and "default" are omitted.
	Presets map[string]string
	// Apps is app-id -> "app=on|off" override. Empty values are omitted.
	Apps map[string]string
	// Sets is terraform -var style key=value (worker_count, node_image, enable_backstage).
	Sets        map[string]string
	AutoApprove bool
}

var presetOrder = []string{
	"resource-profile",
	"image-distribution",
	"network-profile",
	"observability-stack",
	"identity-stack",
	"app-set",
}

func HiddenFromActionDropdown(action string) bool {
	return action == "reset" || action == "state-reset"
}

func ActionUsesAutoApprove(options Options, action string) bool {
	for _, option := range options.ActionMetadata {
		if option.ID == action {
			return option.UsesAutoApprove
		}
	}
	return action == "apply" || action == "reset" || action == "state-reset"
}

func HasAppToggles(options Options, stage string) bool {
	for _, allowed := range options.UIRules.AppToggleStages {
		if allowed == stage {
			return true
		}
	}
	for _, option := range options.Stages {
		if option.ID == stage {
			return option.AppToggles
		}
	}
	return false
}

func AppDefault(options Options, sel Selection, app string) bool {
	tfvar := "enable_app_repo_" + strings.ReplaceAll(app, "-", "_")
	appSet := sel.Presets["app-set"]
	for _, preset := range options.Presets {
		if preset.Group != "app_set" || preset.ID != appSet || preset.Overlay == nil {
			continue
		}
		if value, ok := preset.Overlay[tfvar].(bool); ok {
			return value
		}
	}
	return HasAppToggles(options, sel.Stage)
}

func appDefaultOverride(app string, enabled bool) string {
	if enabled {
		return app + "=on"
	}
	return app + "=off"
}

func Args(options Options, sel Selection, subcommand, standardFlag string) []string {
	args := []string{subcommand, standardFlag}
	args = append(args, "--variant", sel.Variant, "--stage", sel.Stage, "--action", sel.Action)

	seen := map[string]bool{}
	for _, group := range presetOrder {
		value := sel.Presets[group]
		if value == "" || value == "default" {
			continue
		}
		args = append(args, "--preset", group+"="+value)
		seen[group] = true
	}
	for group, value := range sel.Presets {
		if seen[group] || value == "" || value == "default" {
			continue
		}
		args = append(args, "--preset", strings.TrimPrefix(group, "preset_")+"="+value)
	}

	for _, key := range []string{"worker_count", "node_image", "enable_backstage"} {
		if value := sel.Sets[key]; value != "" {
			args = append(args, "--set", key+"="+value)
		}
	}
	for key, value := range sel.Sets {
		if key == "worker_count" || key == "node_image" || key == "enable_backstage" || value == "" {
			continue
		}
		args = append(args, "--set", key+"="+value)
	}

	if HasAppToggles(options, sel.Stage) {
		for _, app := range options.Apps {
			override := sel.Apps[app]
			if override != "" && override != appDefaultOverride(app, AppDefault(options, sel, app)) {
				args = append(args, "--app", override)
			}
		}
	}

	if sel.AutoApprove && ActionUsesAutoApprove(options, sel.Action) {
		args = append(args, "--auto-approve")
	}
	return args
}
