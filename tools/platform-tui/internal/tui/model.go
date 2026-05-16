package tui

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type Config struct {
	RepoRoot       string
	WorkflowScript string
	StatusScript   string
}

type screen int

const (
	screenTarget screen = iota
	screenStage
	screenAction
	screenPreset
	screenSentiment
	screenSubnetcalc
	screenPreview
)

type menuItem struct {
	Label string
	Value string
}

type workflowOptions struct {
	Variants              []variantOption        `json:"variants"`
	Stages                []stageOption          `json:"stages"`
	ActionMetadata        []actionOption         `json:"action_metadata"`
	Apps                  []string               `json:"apps"`
	AppMetadata           []appOption            `json:"app_metadata"`
	Presets               []presetOption         `json:"presets"`
	GuidedSurfaceProfiles []guidedSurfaceProfile `json:"guided_surface_profiles"`
	UIRules               uiRules                `json:"ui_rules"`
}

type variantOption struct {
	ID                string `json:"id"`
	Path              string `json:"path"`
	Label             string `json:"label"`
	GuidedLabel       string `json:"guided_label"`
	GuidedDescription string `json:"guided_description"`
}

type stageOption struct {
	ID             string `json:"id"`
	Label          string `json:"label"`
	Shortcut       string `json:"shortcut"`
	AppToggles     bool   `json:"app_toggles"`
	GuidedHint     string `json:"guided_hint"`
	StageDeltaHint string `json:"stage_delta_hint"`
}

type actionOption struct {
	ID                 string `json:"id"`
	Label              string `json:"label"`
	GuidedLabel        string `json:"guided_label"`
	GuidedDescription  string `json:"guided_description"`
	UsesAutoApprove    bool   `json:"uses_auto_approve"`
	SupportsAppToggles bool   `json:"supports_app_toggles"`
}

type appOption struct {
	ID    string `json:"id"`
	Label string `json:"label"`
}

type guidedSurfaceProfile struct {
	ID          string            `json:"id"`
	Label       string            `json:"label"`
	Variant     string            `json:"variant"`
	Stage       string            `json:"stage"`
	Presets     map[string]string `json:"presets"`
	Description string            `json:"description"`
}

type presetOption struct {
	ID      string                 `json:"id"`
	Group   string                 `json:"group"`
	Overlay map[string]interface{} `json:"overlay"`
}

type uiRules struct {
	GuidedProfileOrder     []string              `json:"guided_profile_order"`
	GuidedActionOrder      []string              `json:"guided_action_order"`
	AppToggleStages        []string              `json:"app_toggle_stages"`
	AppToggleActions       []string              `json:"app_toggle_actions"`
	AppToggleHiddenHint    string                `json:"app_toggle_hidden_hint"`
	AppToggleAvailableHint string                `json:"app_toggle_available_hint"`
	NextApplyStages        map[string][]string   `json:"next_apply_stages_by_stage"`
	PlatformSurfaces       []platformSurfaceFact `json:"platform_surfaces"`
}

type platformSurfaceFact struct {
	Name  string `json:"name"`
	Kind  string `json:"kind"`
	Stage string `json:"stage"`
}

var commandPreviewStyle = lipgloss.NewStyle().
	Bold(true).
	Foreground(lipgloss.Color("81"))

var outputViewportStyle = lipgloss.NewStyle().
	Border(lipgloss.RoundedBorder()).
	BorderForeground(lipgloss.Color("240")).
	Padding(0, 1)

type previewMsg struct {
	Command string
	Err     error
}

type runFinishedMsg struct {
	Output string
	Err    error
}

type runOutputMsg struct {
	Text string
}

type elapsedTickMsg time.Time

type Model struct {
	cfg     Config
	options workflowOptions

	screen screen
	cursor int

	variant                  string
	stage                    string
	stageLabel               string
	action                   string
	appIndex                 int
	appOverrides             map[string]string
	presetResourceProfile    string
	presetImageDistribution  string
	presetNetworkProfile     string
	presetObservabilityStack string
	presetIdentityStack      string
	presetAppSet             string
	customWorkerCount        string
	customNodeImage          string

	previewCommand string
	status         string
	errText        string
	loadingPreview bool
	running        bool
	runSucceeded   bool
	runStartedAt   time.Time
	now            time.Time
	runOutput      string
	lastRunOutput  string
	runCh          chan tea.Msg
	outputViewport viewport.Model
	autoFollow     bool
	width          int
	height         int
}

func New(cfg Config) Model {
	if strings.TrimSpace(cfg.WorkflowScript) == "" {
		cfg.WorkflowScript = "scripts/platform-workflow.sh"
	}
	if strings.TrimSpace(cfg.StatusScript) == "" {
		cfg.StatusScript = "scripts/platform-status.sh"
	}
	outputViewport := viewport.New(76, 8)
	outputViewport.Style = outputViewportStyle
	return Model{
		cfg:            cfg,
		options:        loadWorkflowOptions(cfg),
		screen:         screenTarget,
		appOverrides:   map[string]string{},
		outputViewport: outputViewport,
		autoFollow:     true,
		width:          80,
		height:         24,
	}
}

func loadWorkflowOptions(cfg Config) workflowOptions {
	if options, ok := loadWorkflowOptionsFromScript(cfg); ok {
		return options
	}
	for _, path := range workflowOptionsPaths(cfg) {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		if options, ok := parseWorkflowOptions(data); ok {
			return options
		}
	}
	return fallbackWorkflowOptions()
}

func workflowOptionsPaths(cfg Config) []string {
	rel := filepath.Join("kubernetes", "workflow", "options.json")
	paths := []string{}
	if strings.TrimSpace(cfg.RepoRoot) != "" {
		paths = append(paths, filepath.Join(cfg.RepoRoot, rel))
	}
	paths = append(paths, rel)
	if cwd, err := os.Getwd(); err == nil {
		for dir := cwd; ; dir = filepath.Dir(dir) {
			paths = append(paths, filepath.Join(dir, rel))
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
		}
	}
	return paths
}

func parseWorkflowOptions(data []byte) (workflowOptions, bool) {
	var options workflowOptions
	if err := json.Unmarshal(data, &options); err != nil {
		return workflowOptions{}, false
	}
	if len(options.Variants) == 0 || len(options.Stages) == 0 || len(options.ActionMetadata) == 0 {
		return workflowOptions{}, false
	}
	if len(options.Apps) == 0 {
		options.Apps = []string{"sentiment", "subnetcalc"}
	}
	return options, true
}

func loadWorkflowOptionsFromScript(cfg Config) (workflowOptions, bool) {
	cmd := exec.Command(cfg.WorkflowScript, "options", "--execute", "--output", "json")
	if strings.TrimSpace(cfg.RepoRoot) != "" {
		cmd.Dir = cfg.RepoRoot
	}
	out, err := cmd.Output()
	if err != nil {
		return workflowOptions{}, false
	}
	return parseWorkflowOptions(out)
}

func fallbackWorkflowOptions() workflowOptions {
	return workflowOptions{
		Variants: []variantOption{
			{ID: "kind", Path: "kubernetes/kind", Label: "kind"},
			{ID: "lima", Path: "kubernetes/lima", Label: "lima"},
			{ID: "slicer", Path: "kubernetes/slicer", Label: "slicer"},
		},
		Stages: []stageOption{
			{ID: "100", Label: "cluster", Shortcut: "1", GuidedHint: "1 selects 100 cluster: create or inspect the base local cluster."},
			{ID: "200", Label: "cilium", Shortcut: "2", GuidedHint: "2 selects 200 cilium: install networking before higher platform services."},
			{ID: "300", Label: "hubble", Shortcut: "3", GuidedHint: "3 selects 300 hubble: add Cilium observability."},
			{ID: "400", Label: "argocd", Shortcut: "4", GuidedHint: "4 selects 400 argocd: install GitOps control plane."},
			{ID: "500", Label: "gitea", Shortcut: "5", GuidedHint: "5 selects 500 gitea: add the internal Git server."},
			{ID: "600", Label: "policies", Shortcut: "6", GuidedHint: "6 selects 600 policies: apply cluster policies before app repos."},
			{ID: "700", Label: "app-repos", Shortcut: "7", AppToggles: true, GuidedHint: "7 selects 700 app repos: app toggles start here because app repos exist."},
			{ID: "800", Label: "observability", Shortcut: "8", AppToggles: true, GuidedHint: "8 selects 800 observability: app toggles remain available for workload coverage."},
			{ID: "900", Label: "sso", Shortcut: "9", AppToggles: true, GuidedHint: "9 selects 900 sso: app toggles remain available for end-to-end local apps."},
		},
		ActionMetadata: []actionOption{
			{ID: "readiness", Label: "readiness"},
			{ID: "plan", Label: "plan", SupportsAppToggles: true},
			{ID: "apply", Label: "apply", UsesAutoApprove: true, SupportsAppToggles: true},
			{ID: "status", Label: "status"},
			{ID: "show-urls", Label: "show-urls"},
			{ID: "check-health", Label: "check-health", SupportsAppToggles: true},
			{ID: "check-security", Label: "check-security", SupportsAppToggles: true},
			{ID: "check-rbac", Label: "check-rbac", SupportsAppToggles: true},
		},
		Apps: []string{"sentiment", "subnetcalc"},
		UIRules: uiRules{
			AppToggleStages:        []string{"700", "800", "900"},
			AppToggleActions:       []string{"plan", "apply", "check-health", "check-security", "check-rbac"},
			AppToggleHiddenHint:    "Stages 100-600 hide app toggles because apps are not contained until stage 700.",
			AppToggleAvailableHint: "App overrides are offered only from stage 700 onward, after app repositories exist.",
		},
	}
}

func (m Model) Init() tea.Cmd {
	return nil
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		return m.updateKey(msg)
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.resizeOutputViewport()
		return m, nil
	case previewMsg:
		m.loadingPreview = false
		if msg.Err != nil {
			m.errText = "Preview failed:\n" + msg.Err.Error()
			return m, nil
		}
		m.previewCommand = msg.Command
		return m, nil
	case runFinishedMsg:
		m.running = false
		m.runCh = nil
		if msg.Err != nil {
			m.runSucceeded = false
			if m.runOutput == "" {
				m.errText = "Execution failed:\n" + msg.Err.Error()
			} else {
				m.errText = "Execution failed"
			}
		} else if msg.Output != "" {
			m.runSucceeded = m.action == "apply"
			if m.runOutput == "" {
				m.status = msg.Output
				m.setRunOutput(msg.Output)
			}
			m.focusPreviewItem("back")
		} else {
			m.runSucceeded = m.action == "apply"
			m.status = "Workflow finished"
			m.focusPreviewItem("back")
		}
		return m, nil
	case runOutputMsg:
		m.setRunOutput(appendOutput(m.runOutput, msg.Text))
		return m, waitRunMsg(m.runCh)
	case elapsedTickMsg:
		if !m.running {
			return m, nil
		}
		m.now = time.Time(msg)
		return m, elapsedTickCmd()
	}
	return m, nil
}

func (m Model) updateKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	if m.screen == screenPreview && m.runOutput != "" {
		if updated, handled := m.updateOutputViewportKey(msg); handled {
			return updated, nil
		}
	}

	switch msg.String() {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "esc", "left", "h":
		return m.back(), nil
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
		return m, nil
	case "down", "j":
		if m.cursor < len(m.items())-1 {
			m.cursor++
		}
		return m, nil
	case "r":
		if m.screen == screenStage {
			return m.selectItemValue("reset")
		}
	case "t":
		if m.screen == screenStage {
			return m.selectItemValue("state-reset")
		}
	case "enter", " ":
		return m.selectCurrent()
	}
	if m.screen == screenStage && len(msg.Runes) == 1 {
		if value, ok := m.stageShortcutValue(msg.Runes[0]); ok {
			return m.selectItemValue(value)
		}
	}
	return m, nil
}

func (m Model) selectItemValue(value string) (tea.Model, tea.Cmd) {
	for i, item := range m.items() {
		if item.Value == value {
			m.cursor = i
			return m.selectCurrent()
		}
	}
	return m, nil
}

func (m Model) selectCurrent() (tea.Model, tea.Cmd) {
	items := m.items()
	if len(items) == 0 || m.cursor < 0 || m.cursor >= len(items) {
		return m, nil
	}
	item := items[m.cursor]
	m.errText = ""

	switch item.Value {
	case "back":
		return m.back(), nil
	case "quit":
		return m, tea.Quit
	}
	if strings.HasPrefix(item.Value, "next:") {
		return m.selectNext(item.Value)
	}

	switch m.screen {
	case screenTarget:
		switch item.Value {
		case "quit":
			return m, tea.Quit
		case "status":
			m.variant = ""
			m.screen = screenPreview
			m.previewCommand = "make status"
			return m, nil
		default:
			m.variant = item.Value
			m.screen = screenStage
			m.cursor = 0
			return m, nil
		}
	case screenStage:
		m.stageLabel = item.Label
		if item.Value == "reset" || item.Value == "state-reset" {
			m.stage = "100"
			m.action = item.Value
			m.screen = screenPreview
			m.cursor = 0
			return m, m.loadPreviewCmd()
		}
		m.stage = item.Value
		m.screen = screenAction
		m.cursor = 0
		return m, nil
	case screenAction:
		if item.Value == "preset" {
			m.screen = screenPreset
			m.cursor = 0
			return m, nil
		}
		m.action = item.Value
		m.cursor = 0
		if m.hasAppToggles() && m.actionSupportsAppToggles(m.action) {
			m.appIndex = 0
			m.appOverrides = map[string]string{}
			m.screen = screenSentiment
			return m, nil
		}
		m.screen = screenPreview
		return m, m.loadPreviewCmd()
	case screenPreset:
		m.applyPresetBundle(item.Value)
		m.screen = screenAction
		m.cursor = 0
		return m, nil
	case screenSentiment:
		return m.selectAppOverride(item.Value)
	case screenSubnetcalc:
		return m.selectAppOverride(item.Value)
	case screenPreview:
		switch item.Value {
		case "run":
			if m.running {
				return m, nil
			}
			m.running = true
			m.runSucceeded = false
			m.status = ""
			if m.runOutput != "" {
				m.lastRunOutput = m.runOutput
			}
			m.setRunOutput("")
			m.autoFollow = true
			m.runStartedAt = time.Now()
			m.now = m.runStartedAt
			m.runCh = make(chan tea.Msg)
			return m, tea.Batch(m.runWorkflowCmd(m.runCh), elapsedTickCmd())
		case "back":
			return m.back(), nil
		case "quit":
			return m, tea.Quit
		}
	}
	return m, nil
}

func (m Model) back() Model {
	m.cursor = 0
	m.errText = ""
	m.status = ""
	m.runSucceeded = false
	switch m.screen {
	case screenTarget:
		return m
	case screenStage:
		m.screen = screenTarget
	case screenAction:
		m.screen = screenStage
	case screenPreset:
		m.screen = screenAction
	case screenSentiment:
		m.screen = screenAction
	case screenSubnetcalc:
		if m.appIndex > 1 {
			m.appIndex--
			m.screen = screenSubnetcalc
		} else {
			m.appIndex = 0
			m.screen = screenSentiment
		}
	case screenPreview:
		if m.action == "reset" || m.action == "state-reset" {
			m.screen = screenStage
		} else if !m.hasAppToggles() || !m.actionSupportsAppToggles(m.action) {
			m.screen = screenAction
		} else {
			if len(m.options.Apps) <= 1 {
				m.screen = screenSentiment
			} else {
				m.appIndex = len(m.options.Apps) - 1
				m.screen = screenSubnetcalc
			}
		}
	}
	return m
}

func (m *Model) clearRunResult() {
	m.status = ""
	m.errText = ""
	m.runSucceeded = false
	if m.runOutput != "" {
		m.lastRunOutput = m.runOutput
	}
	m.setRunOutput("")
	m.autoFollow = true
}

func (m *Model) focusPreviewItem(value string) {
	items := m.items()
	for i, item := range items {
		if item.Value == value {
			m.cursor = i
			return
		}
	}
}

func (m *Model) setRunOutput(output string) {
	m.runOutput = output
	m.outputViewport.SetContent(output)
	if m.autoFollow {
		m.outputViewport.GotoBottom()
	}
}

func (m Model) updateOutputViewportKey(msg tea.KeyMsg) (Model, bool) {
	before := m.outputViewport.YOffset
	handled := true

	switch msg.String() {
	case "pgup", "u", "ctrl+u":
		m.outputViewport.PageUp()
		m.autoFollow = false
	case "pgdown", "d", "ctrl+d":
		m.outputViewport.PageDown()
		m.autoFollow = m.outputViewport.AtBottom()
	case "home":
		m.outputViewport.GotoTop()
		m.autoFollow = false
	case "end":
		m.outputViewport.GotoBottom()
		m.autoFollow = true
	default:
		handled = false
	}
	if handled && m.outputViewport.YOffset != before {
		return m, true
	}
	return m, handled
}

func (m *Model) resizeOutputViewport() {
	width := m.width - 2
	if width < 40 {
		width = 40
	}
	height := m.height - 15
	if height < 6 {
		height = 6
	}
	if height > 18 {
		height = 18
	}
	m.outputViewport.Width = width
	m.outputViewport.Height = height
	m.outputViewport.Style = outputViewportStyle
	m.outputViewport.SetContent(m.runOutput)
	if m.autoFollow {
		m.outputViewport.GotoBottom()
	}
}

func (m Model) items() []menuItem {
	switch m.screen {
	case screenTarget:
		items := make([]menuItem, 0, len(m.options.Variants)+2)
		for _, variant := range m.options.Variants {
			label := variant.Label
			if label == "" {
				label = variant.ID
			}
			items = append(items, menuItem{Label: label, Value: variant.ID})
		}
		items = append(items, menuItem{Label: "Status", Value: "status"}, menuItem{Label: "Quit", Value: "quit"})
		return items
	case screenStage:
		items := make([]menuItem, 0, len(m.options.Stages)+2)
		for _, stage := range m.options.Stages {
			items = append(items, menuItem{Label: fmt.Sprintf("%s %s", stage.ID, strings.ReplaceAll(stage.Label, "-", " ")), Value: stage.ID})
		}
		items = append(items, menuItem{Label: "Reset variant", Value: "reset"})
		items = append(items, menuItem{Label: "Terraform state reset", Value: "state-reset"})
		return withNavigation(items)
	case screenAction:
		items := []menuItem{{Label: "Preset bundle", Value: "preset"}}
		for _, action := range m.options.ActionMetadata {
			if action.ID == "reset" || action.ID == "state-reset" {
				continue
			}
			label := action.Label
			if label == "" {
				label = action.ID
			}
			items = append(items, menuItem{Label: label, Value: action.ID})
		}
		return withNavigation(items)
	case screenPreset:
		items := make([]menuItem, 0, len(m.options.GuidedSurfaceProfiles))
		profilesByID := make(map[string]guidedSurfaceProfile, len(m.options.GuidedSurfaceProfiles))
		for _, profile := range m.options.GuidedSurfaceProfiles {
			profilesByID[profile.ID] = profile
		}
		seen := map[string]bool{}
		for _, id := range m.options.UIRules.GuidedProfileOrder {
			profile, ok := profilesByID[id]
			if !ok {
				continue
			}
			items = append(items, menuItem{Label: profile.Label, Value: profile.ID})
			seen[id] = true
		}
		for _, profile := range m.options.GuidedSurfaceProfiles {
			if !seen[profile.ID] {
				items = append(items, menuItem{Label: profile.Label, Value: profile.ID})
			}
		}
		return withNavigation(items)
	case screenSentiment:
		return withNavigation(appItems(m.currentApp(), m.appDefault(m.currentApp())))
	case screenSubnetcalc:
		return withNavigation(appItems(m.currentApp(), m.appDefault(m.currentApp())))
	case screenPreview:
		items := []menuItem{
			{Label: "Execute", Value: "run"},
		}
		items = append(items, m.nextItems()...)
		items = append(items,
			menuItem{Label: "Back", Value: "back"},
			menuItem{Label: "Quit", Value: "quit"},
		)
		return items
	default:
		return nil
	}
}

func (m Model) nextItems() []menuItem {
	if !m.runSucceeded || m.action != "apply" {
		return nil
	}
	stages := m.options.UIRules.NextApplyStages[m.stage]
	items := make([]menuItem, 0, len(stages))
	for _, stage := range stages {
		items = append(items, menuItem{
			Label: fmt.Sprintf("%s apply", stageDisplay(stage)),
			Value: "next:" + stage,
		})
	}
	return items
}

func stageDisplay(stage string) string {
	return stage
}

func (m Model) stageShortcutValue(shortcut rune) (string, bool) {
	value := string(shortcut)
	for _, stage := range m.options.Stages {
		if stage.Shortcut == value {
			return stage.ID, true
		}
	}
	return "", false
}

func (m Model) selectNext(value string) (tea.Model, tea.Cmd) {
	stage := strings.TrimPrefix(value, "next:")
	m.stage = stage
	m.stageLabel = stageDisplay(stage)
	m.action = "apply"
	m.appIndex = 0
	m.appOverrides = map[string]string{}
	m.previewCommand = ""
	m.status = ""
	m.errText = ""
	m.runSucceeded = false
	if m.runOutput != "" {
		m.lastRunOutput = m.runOutput
	}
	m.autoFollow = true
	m.screen = screenPreview
	m.cursor = 0
	return m, m.loadPreviewCmd()
}

func (m Model) currentApp() string {
	if len(m.options.Apps) == 0 {
		return ""
	}
	if m.appIndex < 0 {
		return m.options.Apps[0]
	}
	if m.appIndex >= len(m.options.Apps) {
		return m.options.Apps[len(m.options.Apps)-1]
	}
	return m.options.Apps[m.appIndex]
}

func (m Model) selectAppOverride(value string) (tea.Model, tea.Cmd) {
	app := m.currentApp()
	if m.appOverrides == nil {
		m.appOverrides = map[string]string{}
	}
	if app != "" {
		m.appOverrides[app] = value
	}
	m.appIndex++
	if m.appIndex < len(m.options.Apps) {
		if m.appIndex == 0 {
			m.screen = screenSentiment
		} else {
			m.screen = screenSubnetcalc
		}
		m.cursor = 0
		return m, nil
	}
	m.screen = screenPreview
	m.cursor = 0
	return m, m.loadPreviewCmd()
}

func withNavigation(items []menuItem) []menuItem {
	return append(items,
		menuItem{Label: "Back", Value: "back"},
		menuItem{Label: "Quit", Value: "quit"},
	)
}

func appItems(app string, enabled bool) []menuItem {
	if enabled {
		return []menuItem{
			{Label: fmt.Sprintf("%s enabled (default: enabled)", app), Value: app + "=on"},
			{Label: fmt.Sprintf("%s disabled", app), Value: app + "=off"},
		}
	}
	return []menuItem{
		{Label: fmt.Sprintf("%s disabled (default: disabled)", app), Value: app + "=off"},
		{Label: fmt.Sprintf("%s enabled", app), Value: app + "=on"},
	}
}

func (m *Model) applyPresetBundle(bundle string) {
	m.presetResourceProfile = ""
	m.presetImageDistribution = ""
	m.presetNetworkProfile = ""
	m.presetObservabilityStack = ""
	m.presetIdentityStack = ""
	m.presetAppSet = ""
	m.customWorkerCount = ""
	m.customNodeImage = ""
	for _, profile := range m.options.GuidedSurfaceProfiles {
		if profile.ID != bundle {
			continue
		}
		if profile.Variant != "" {
			m.variant = profile.Variant
		}
		if profile.Stage != "" {
			m.stage = profile.Stage
			m.stageLabel = stageDisplay(profile.Stage)
		}
		m.presetResourceProfile = profile.Presets["resource_profile"]
		m.presetImageDistribution = profile.Presets["image_distribution"]
		m.presetNetworkProfile = profile.Presets["network_profile"]
		m.presetObservabilityStack = profile.Presets["observability_stack"]
		m.presetIdentityStack = profile.Presets["identity_stack"]
		m.presetAppSet = profile.Presets["app_set"]
		return
	}
}

func (m Model) appDefault(app string) bool {
	tfvar := appTFVarName(app)
	for _, preset := range m.options.Presets {
		if preset.Group != "app_set" || preset.ID != m.presetAppSet || preset.Overlay == nil {
			continue
		}
		if value, ok := preset.Overlay[tfvar].(bool); ok {
			return value
		}
	}
	return m.hasAppToggles()
}

func (m Model) hasAppToggles() bool {
	for _, stage := range m.options.UIRules.AppToggleStages {
		if stage == m.stage {
			return true
		}
	}
	for _, stage := range m.options.Stages {
		if stage.ID == m.stage {
			return stage.AppToggles
		}
	}
	return false
}

func (m Model) actionSupportsAppToggles(action string) bool {
	for _, allowed := range m.options.UIRules.AppToggleActions {
		if allowed == action {
			return true
		}
	}
	for _, option := range m.options.ActionMetadata {
		if option.ID == action {
			return option.SupportsAppToggles
		}
	}
	return false
}

func (m Model) workflowArgs(subcommand string) []string {
	args := []string{subcommand, "--execute"}
	if subcommand == "preview" {
		args = append(args, "--output", "json")
	}
	args = append(args, "--variant", m.variant, "--stage", m.stage, "--action", m.action)
	if m.presetResourceProfile != "" {
		args = append(args, "--preset", "resource-profile="+m.presetResourceProfile)
	}
	if m.presetImageDistribution != "" {
		args = append(args, "--preset", "image-distribution="+m.presetImageDistribution)
	}
	if m.presetNetworkProfile != "" {
		args = append(args, "--preset", "network-profile="+m.presetNetworkProfile)
	}
	if m.presetObservabilityStack != "" {
		args = append(args, "--preset", "observability-stack="+m.presetObservabilityStack)
	}
	if m.presetIdentityStack != "" {
		args = append(args, "--preset", "identity-stack="+m.presetIdentityStack)
	}
	if m.presetAppSet != "" {
		args = append(args, "--preset", "app-set="+m.presetAppSet)
	}
	if m.customWorkerCount != "" {
		args = append(args, "--set", "worker_count="+m.customWorkerCount)
	}
	if m.customNodeImage != "" {
		args = append(args, "--set", "node_image="+m.customNodeImage)
	}
	for _, app := range m.options.Apps {
		override := m.appOverrides[app]
		if override != "" && override != appDefaultOverride(app, m.appDefault(app)) {
			args = append(args, "--app", override)
		}
	}
	if m.actionUsesAutoApprove(m.action) {
		args = append(args, "--auto-approve")
	}
	return args
}

func (m Model) actionUsesAutoApprove(action string) bool {
	for _, option := range m.options.ActionMetadata {
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

func (m Model) loadPreviewCmd() tea.Cmd {
	args := m.workflowArgs("preview")
	return func() tea.Msg {
		cmd := exec.Command(m.cfg.WorkflowScript, args...)
		if m.cfg.RepoRoot != "" {
			cmd.Dir = m.cfg.RepoRoot
		}
		out, err := cmd.CombinedOutput()
		if err != nil {
			return previewMsg{Err: commandErr(err, out)}
		}
		var payload struct {
			Command string `json:"command"`
		}
		if err := json.Unmarshal(out, &payload); err != nil {
			return previewMsg{Err: fmt.Errorf("parse preview: %w", err)}
		}
		return previewMsg{Command: payload.Command}
	}
}

func (m Model) runWorkflowCmd(ch chan tea.Msg) tea.Cmd {
	args := m.workflowArgs("apply")
	return startRunCmd(m.cfg, args, ch)
}

func startRunCmd(cfg Config, args []string, ch chan tea.Msg) tea.Cmd {
	return func() tea.Msg {
		go func() {
			defer close(ch)
			var captured bytes.Buffer

			send := func(text string) {
				text = strings.TrimRight(text, "\r\n")
				if text == "" {
					return
				}
				captured.WriteString(text)
				captured.WriteByte('\n')
				ch <- runOutputMsg{Text: text}
			}

			cmd := exec.Command(cfg.WorkflowScript, args...)
			if cfg.RepoRoot != "" {
				cmd.Dir = cfg.RepoRoot
			}

			stdout, err := cmd.StdoutPipe()
			if err != nil {
				ch <- runFinishedMsg{Err: err}
				return
			}
			stderr, err := cmd.StderrPipe()
			if err != nil {
				ch <- runFinishedMsg{Err: err}
				return
			}
			if err := cmd.Start(); err != nil {
				ch <- runFinishedMsg{Err: err}
				return
			}

			done := make(chan struct{}, 2)
			stream := func(r io.Reader) {
				defer func() { done <- struct{}{} }()
				scanner := bufio.NewScanner(r)
				for scanner.Scan() {
					send(scanner.Text())
				}
				if err := scanner.Err(); err != nil {
					send(err.Error())
				}
			}
			go stream(stdout)
			go stream(stderr)
			<-done
			<-done

			if err := cmd.Wait(); err != nil {
				ch <- runFinishedMsg{Err: commandErr(err, captured.Bytes())}
				return
			}
			ch <- runFinishedMsg{Output: strings.TrimSpace(captured.String())}
		}()
		msg, ok := <-ch
		if !ok {
			return nil
		}
		return msg
	}
}

func waitRunMsg(ch chan tea.Msg) tea.Cmd {
	return func() tea.Msg {
		if ch == nil {
			return nil
		}
		msg, ok := <-ch
		if !ok {
			return nil
		}
		return msg
	}
}

func elapsedTickCmd() tea.Cmd {
	return tea.Tick(time.Second, func(t time.Time) tea.Msg {
		return elapsedTickMsg(t)
	})
}

func appendOutput(existing, next string) string {
	next = strings.TrimRight(next, "\r\n")
	if next == "" {
		return existing
	}
	if existing == "" {
		return next
	}
	return existing + "\n" + next
}

func commandErr(err error, output []byte) error {
	if err == nil {
		return nil
	}
	if text := strings.TrimSpace(string(output)); text != "" {
		return fmt.Errorf("%s", text)
	}
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		stderr := strings.TrimSpace(string(exitErr.Stderr))
		if stderr != "" {
			return fmt.Errorf("%w: %s", err, stderr)
		}
	}
	return err
}

func (m Model) View() string {
	var b bytes.Buffer
	title := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("99")).Render("Platform TUI")
	subtitle := lipgloss.NewStyle().Foreground(lipgloss.Color("245")).Render("Choose a variant, stage, optional presets, action, and app toggles.")
	fmt.Fprintf(&b, "%s\n%s\n\n", title, subtitle)
	fmt.Fprintf(&b, "%s\n\n", m.breadcrumb())

	if m.screen == screenPreview {
		if m.previewCommand == "" {
			fmt.Fprintf(&b, "%s\n\n", commandPreviewStyle.Render("Command: loading preview..."))
		} else {
			fmt.Fprintf(&b, "%s\n\n", commandPreviewStyle.Render("Command: "+m.previewCommand))
		}
	}
	if m.screen == screenPreview && m.running {
		fmt.Fprintf(&b, "%s\n", lipgloss.NewStyle().Foreground(lipgloss.Color("214")).Render("Running workflow"))
		fmt.Fprintf(&b, "%s\n", lipgloss.NewStyle().Foreground(lipgloss.Color("245")).Render("Elapsed: "+m.elapsedText()))
		if m.previewCommand != "" {
			fmt.Fprintf(&b, "%s\n", lipgloss.NewStyle().Foreground(lipgloss.Color("245")).Render("Executing: "+m.previewCommand))
		}
		fmt.Fprintln(&b)
	}
	if m.screen == screenPreview && m.runOutput != "" {
		fmt.Fprintf(&b, "%s\n", m.outputViewport.View())
		scrollStatus := fmt.Sprintf("output %d/%d", m.outputViewport.YOffset+m.outputViewport.VisibleLineCount(), m.outputViewport.TotalLineCount())
		if m.autoFollow {
			scrollStatus += " follow"
		}
		fmt.Fprintf(&b, "%s\n\n", lipgloss.NewStyle().Foreground(lipgloss.Color("245")).Render(scrollStatus+"  pgup/pgdn scroll  home/end jump"))
	} else if m.screen == screenPreview && m.lastRunOutput != "" {
		fmt.Fprintf(&b, "%s\n", lipgloss.NewStyle().Foreground(lipgloss.Color("245")).Render("Latest output from previous command:"))
		fmt.Fprintf(&b, "%s\n\n", outputViewportStyle.Width(m.outputViewport.Width).Height(m.outputViewport.Height).Render(m.lastRunOutput))
	}
	if m.errText != "" {
		fmt.Fprintf(&b, "%s\n\n", lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Render(m.errText))
	}
	if m.status != "" {
		fmt.Fprintf(&b, "%s\n\n", m.status)
	}

	items := m.items()
	for i, item := range items {
		cursor := "  "
		if i == m.cursor {
			cursor = "➜ "
		}
		fmt.Fprintf(&b, "%s%s\n", cursor, item.Label)
	}
	if hint := m.inlineHint(); hint != "" {
		fmt.Fprintf(&b, "\n%s\n", lipgloss.NewStyle().Foreground(lipgloss.Color("245")).Render(hint))
	}
	fmt.Fprintf(&b, "\n%s\n", lipgloss.NewStyle().Foreground(lipgloss.Color("245")).Render("↑/↓ or j/k move  enter select  esc back  q quit"))
	return b.String()
}

func (m Model) breadcrumb() string {
	parts := []string{"Guided workflow"}
	if m.variant != "" {
		parts = append(parts, m.variant)
	}
	if m.stage != "" && m.action != "reset" && m.action != "state-reset" {
		parts = append(parts, m.stage)
	}
	if m.action != "" {
		parts = append(parts, m.action)
	}
	if preset := m.presetSummary(); preset != "" {
		parts = append(parts, preset)
	}
	return strings.Join(parts, " / ")
}

func (m Model) presetSummary() string {
	presets := []string{}
	if m.presetResourceProfile != "" {
		presets = append(presets, "resource="+m.presetResourceProfile)
	}
	if m.presetImageDistribution != "" {
		presets = append(presets, "images="+m.presetImageDistribution)
	}
	if m.presetNetworkProfile != "" {
		presets = append(presets, "network="+m.presetNetworkProfile)
	}
	if m.presetObservabilityStack != "" {
		presets = append(presets, "observability="+m.presetObservabilityStack)
	}
	if m.presetIdentityStack != "" {
		presets = append(presets, "identity="+m.presetIdentityStack)
	}
	if m.presetAppSet != "" {
		presets = append(presets, "apps="+m.presetAppSet)
	}
	if m.customWorkerCount != "" {
		presets = append(presets, "worker_count="+m.customWorkerCount)
	}
	if m.customNodeImage != "" {
		presets = append(presets, "node_image="+m.customNodeImage)
	}
	return strings.Join(presets, ",")
}

func (m Model) inlineHint() string {
	item := m.selectedItem()
	if item.Value == "" && item.Label == "" {
		return ""
	}
	switch m.screen {
	case screenTarget:
		if item.Value == "status" {
			return "Shows root runtime status without changing any stack."
		}
		if item.Value != "quit" {
			return "Pick the local runtime variant before choosing a stage."
		}
	case screenStage:
		return m.stageHint(item)
	case screenAction:
		return m.actionHint(item)
	case screenPreset:
		return "Preset bundles set the same workflow --preset overlays as the browser UI."
	case screenSentiment, screenSubnetcalc:
		if m.options.UIRules.AppToggleAvailableHint != "" {
			return m.options.UIRules.AppToggleAvailableHint
		}
		return "App overrides are offered only from stage 700 onward, after app repositories exist."
	case screenPreview:
		if item.Value == "run" {
			return "Executes the exact command shown above through scripts/platform-workflow.sh --execute."
		}
		if strings.HasPrefix(item.Value, "next:") {
			return "Shortcut to the next useful apply stage after this successful run."
		}
	}
	return ""
}

func (m Model) selectedItem() menuItem {
	items := m.items()
	if m.cursor < 0 || m.cursor >= len(items) {
		return menuItem{}
	}
	return items[m.cursor]
}

func (m Model) stageHint(item menuItem) string {
	if item.Value != "reset" && item.Value != "state-reset" {
		if stage, ok := m.stageOption(item.Value); ok && stage.GuidedHint != "" {
			return stage.GuidedHint
		}
	}
	switch item.Value {
	case "100":
		return "1 selects 100 cluster: create or inspect the base local cluster."
	case "200":
		return "2 selects 200 cilium: install networking before higher platform services."
	case "300":
		return "3 selects 300 hubble: add Cilium observability."
	case "400":
		return "4 selects 400 argocd: install GitOps control plane."
	case "500":
		return "5 selects 500 gitea: add the internal Git server."
	case "600":
		return "6 selects 600 policies: apply cluster policies before app repos."
	case "700":
		return "7 selects 700 app repos: app toggles start here because app repos exist."
	case "800":
		return "8 selects 800 observability: app toggles remain available for workload coverage."
	case "900":
		return "9 selects 900 sso: app toggles remain available for end-to-end local apps."
	case "reset":
		return "r resets the selected variant through the workflow script."
	case "state-reset":
		return "t resets Terraform state for the selected variant."
	default:
		if m.options.UIRules.AppToggleHiddenHint != "" {
			return m.options.UIRules.AppToggleHiddenHint
		}
		return "Stages 100-600 hide app toggles because apps are not contained until stage 700."
	}
}

func (m Model) actionHint(item menuItem) string {
	if item.Value == "preset" {
		return "Choose optional preset overlays before selecting plan, apply, or a read-only helper."
	}
	if !m.hasAppToggles() {
		return fmt.Sprintf("%s on stage %s skips app toggles; %s", item.Label, stageDisplay(m.stage), appToggleStageSummary(m.options.UIRules.AppToggleStages))
	}
	return fmt.Sprintf("%s on stage %s can include app toggle overrides before preview.", item.Label, stageDisplay(m.stage))
}

func (m Model) stageOption(stageID string) (stageOption, bool) {
	for _, stage := range m.options.Stages {
		if stage.ID == stageID {
			return stage, true
		}
	}
	return stageOption{}, false
}

func appToggleStageSummary(stages []string) string {
	if len(stages) == 0 {
		return "app choices are unavailable for this stage."
	}
	if len(stages) == 1 {
		return "app choices appear at stage " + stages[0] + "."
	}
	return "app choices appear at stages " + strings.Join(stages[:len(stages)-1], ", ") + ", and " + stages[len(stages)-1] + "."
}

func (m Model) elapsedText() string {
	if m.runStartedAt.IsZero() {
		return "0s"
	}
	now := m.now
	if now.IsZero() {
		now = time.Now()
	}
	if now.Before(m.runStartedAt) {
		now = m.runStartedAt
	}
	elapsed := now.Sub(m.runStartedAt).Round(time.Second)
	minutes := int(elapsed.Minutes())
	seconds := int(elapsed.Seconds()) % 60
	if minutes > 0 {
		return fmt.Sprintf("%dm%02ds", minutes, seconds)
	}
	return fmt.Sprintf("%ds", seconds)
}
