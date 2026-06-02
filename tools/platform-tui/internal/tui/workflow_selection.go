package tui

import "strings"

type WorkflowSelection struct {
	Options                  workflowOptions
	Variant                  string
	Stage                    string
	Action                   string
	AppOverrides             map[string]string
	PresetResourceProfile    string
	PresetImageDistribution  string
	PresetNetworkProfile     string
	PresetObservabilityStack string
	PresetIdentityStack      string
	PresetAppSet             string
	CustomWorkerCount        string
	CustomNodeImage          string
}

func (s WorkflowSelection) WorkflowArgs(subcommand string) []string {
	args := []string{subcommand, "--execute"}
	if subcommand == "preview" {
		args = append(args, "--output", "json")
	}
	args = append(args, "--variant", s.Variant, "--stage", s.Stage, "--action", s.Action)
	if s.PresetResourceProfile != "" {
		args = append(args, "--preset", "resource-profile="+s.PresetResourceProfile)
	}
	if s.PresetImageDistribution != "" {
		args = append(args, "--preset", "image-distribution="+s.PresetImageDistribution)
	}
	if s.PresetNetworkProfile != "" {
		args = append(args, "--preset", "network-profile="+s.PresetNetworkProfile)
	}
	if s.PresetObservabilityStack != "" {
		args = append(args, "--preset", "observability-stack="+s.PresetObservabilityStack)
	}
	if s.PresetIdentityStack != "" {
		args = append(args, "--preset", "identity-stack="+s.PresetIdentityStack)
	}
	if s.PresetAppSet != "" {
		args = append(args, "--preset", "app-set="+s.PresetAppSet)
	}
	if s.CustomWorkerCount != "" {
		args = append(args, "--set", "worker_count="+s.CustomWorkerCount)
	}
	if s.CustomNodeImage != "" {
		args = append(args, "--set", "node_image="+s.CustomNodeImage)
	}
	if s.HasAppToggles() {
		for _, app := range s.Options.Apps {
			override := s.AppOverrides[app]
			if override != "" && override != appDefaultOverride(app, s.AppDefault(app)) {
				args = append(args, "--app", override)
			}
		}
	}
	if s.ActionUsesAutoApprove(s.Action) {
		args = append(args, "--auto-approve")
	}
	return args
}

func (s WorkflowSelection) AppDefault(app string) bool {
	tfvar := appTFVarName(app)
	for _, preset := range s.Options.Presets {
		if preset.Group != "app_set" || preset.ID != s.PresetAppSet || preset.Overlay == nil {
			continue
		}
		if value, ok := preset.Overlay[tfvar].(bool); ok {
			return value
		}
	}
	return s.HasAppToggles()
}

func (s WorkflowSelection) HasAppToggles() bool {
	for _, stage := range s.Options.UIRules.AppToggleStages {
		if stage == s.Stage {
			return true
		}
	}
	for _, stage := range s.Options.Stages {
		if stage.ID == s.Stage {
			return stage.AppToggles
		}
	}
	return false
}

func (s WorkflowSelection) ActionSupportsAppToggles(action string) bool {
	for _, allowed := range s.Options.UIRules.AppToggleActions {
		if allowed == action {
			return true
		}
	}
	for _, option := range s.Options.ActionMetadata {
		if option.ID == action {
			return option.SupportsAppToggles
		}
	}
	return false
}

func (s WorkflowSelection) ActionUsesAutoApprove(action string) bool {
	for _, option := range s.Options.ActionMetadata {
		if option.ID == action {
			return option.UsesAutoApprove
		}
	}
	return action == "apply" || action == "reset" || action == "state-reset"
}

func appDefaultOverride(app string, enabled bool) string {
	if enabled {
		return app + "=on"
	}
	return app + "=off"
}

func appTFVarName(app string) string {
	return "enable_app_repo_" + strings.ReplaceAll(app, "-", "_")
}
