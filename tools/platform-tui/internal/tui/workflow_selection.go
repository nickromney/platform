package tui

import (
	workflowcore "github.com/nickromney/platform/tools/platform-workflow-core"
)

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

func (s WorkflowSelection) coreOptions() workflowcore.Options {
	options := workflowcore.Options{
		Apps: append([]string(nil), s.Options.Apps...),
		UIRules: workflowcore.UIRules{
			AppToggleStages:  append([]string(nil), s.Options.UIRules.AppToggleStages...),
			AppToggleActions: append([]string(nil), s.Options.UIRules.AppToggleActions...),
		},
	}
	for _, stage := range s.Options.Stages {
		options.Stages = append(options.Stages, workflowcore.StageOption{ID: stage.ID, AppToggles: stage.AppToggles})
	}
	for _, action := range s.Options.ActionMetadata {
		options.ActionMetadata = append(options.ActionMetadata, workflowcore.ActionOption{
			ID:                 action.ID,
			UsesAutoApprove:    action.UsesAutoApprove,
			SupportsAppToggles: action.SupportsAppToggles,
		})
	}
	for _, preset := range s.Options.Presets {
		options.Presets = append(options.Presets, workflowcore.PresetOption{Group: preset.Group, ID: preset.ID, Overlay: preset.Overlay})
	}
	return options
}

func (s WorkflowSelection) coreSelection() workflowcore.Selection {
	presets := map[string]string{
		"resource-profile":    s.PresetResourceProfile,
		"image-distribution":  s.PresetImageDistribution,
		"network-profile":     s.PresetNetworkProfile,
		"observability-stack": s.PresetObservabilityStack,
		"identity-stack":      s.PresetIdentityStack,
		"app-set":             s.PresetAppSet,
	}
	sets := map[string]string{}
	if s.CustomWorkerCount != "" {
		sets["worker_count"] = s.CustomWorkerCount
	}
	if s.CustomNodeImage != "" {
		sets["node_image"] = s.CustomNodeImage
	}
	return workflowcore.Selection{
		Variant:     s.Variant,
		Stage:       s.Stage,
		Action:      s.Action,
		Presets:     presets,
		Apps:        s.AppOverrides,
		Sets:        sets,
		AutoApprove: s.ActionUsesAutoApprove(s.Action),
	}
}

func (s WorkflowSelection) WorkflowArgs(subcommand string) []string {
	args := workflowcore.Args(s.coreOptions(), s.coreSelection(), subcommand, "--execute")
	if subcommand == "preview" {
		args = append(args[:2], append([]string{"--output", "json"}, args[2:]...)...)
	}
	return args
}

func (s WorkflowSelection) AppDefault(app string) bool {
	return workflowcore.AppDefault(s.coreOptions(), s.coreSelection(), app)
}

func (s WorkflowSelection) HasAppToggles() bool {
	return workflowcore.HasAppToggles(s.coreOptions(), s.Stage)
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
	return workflowcore.ActionUsesAutoApprove(s.coreOptions(), action)
}
