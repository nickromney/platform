package tui

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os/exec"
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
	screenSentiment
	screenSubnetcalc
	screenPreview
)

type menuItem struct {
	Label string
	Value string
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
	cfg Config

	screen screen
	cursor int

	target     string
	stage      string
	stageLabel string
	action     string
	sentiment  string
	subnetcalc string

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
		screen:         screenTarget,
		outputViewport: outputViewport,
		autoFollow:     true,
		width:          80,
		height:         24,
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
		if value, ok := stageShortcutValue(msg.Runes[0], m.target); ok {
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
			m.target = ""
			m.screen = screenPreview
			m.previewCommand = "make status"
			return m, nil
		default:
			m.target = item.Value
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
		m.action = item.Value
		m.cursor = 0
		if m.hasAppToggles() {
			m.screen = screenSentiment
			return m, nil
		}
		m.screen = screenPreview
		return m, m.loadPreviewCmd()
	case screenSentiment:
		m.sentiment = item.Value
		m.screen = screenSubnetcalc
		m.cursor = 0
		return m, nil
	case screenSubnetcalc:
		m.subnetcalc = item.Value
		m.screen = screenPreview
		m.cursor = 0
		return m, m.loadPreviewCmd()
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
	case screenSentiment:
		m.screen = screenAction
	case screenSubnetcalc:
		m.screen = screenSentiment
	case screenPreview:
		if m.action == "reset" || m.action == "state-reset" {
			m.screen = screenStage
		} else if !m.hasAppToggles() {
			m.screen = screenAction
		} else {
			m.screen = screenSubnetcalc
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
		return []menuItem{
			{Label: "kind", Value: "kind"},
			{Label: "lima", Value: "lima"},
			{Label: "slicer", Value: "slicer"},
			{Label: "Status", Value: "status"},
			{Label: "Quit", Value: "quit"},
		}
	case screenStage:
		items := []menuItem{
			{Label: "100 cluster", Value: "100"},
			{Label: "200 cilium", Value: "200"},
			{Label: "300 hubble", Value: "300"},
			{Label: "400 argocd", Value: "400"},
			{Label: "500 gitea", Value: "500"},
			{Label: "600 policies", Value: "600"},
			{Label: "700 app repos", Value: "700"},
			{Label: "800 observability", Value: "800"},
			{Label: "900 sso", Value: "900"},
		}
		if m.target == "kind" {
			items = append(items, menuItem{Label: "950 local-idp", Value: "950-local-idp"})
		}
		items = append(items, menuItem{Label: "Reset target", Value: "reset"})
		items = append(items, menuItem{Label: "Terraform state reset", Value: "state-reset"})
		return withNavigation(items)
	case screenAction:
		return withNavigation([]menuItem{
			{Label: "plan", Value: "plan"},
			{Label: "apply", Value: "apply"},
			{Label: "status", Value: "status"},
			{Label: "show-urls", Value: "show-urls"},
			{Label: "check-health", Value: "check-health"},
			{Label: "check-security", Value: "check-security"},
			{Label: "check-rbac", Value: "check-rbac"},
		})
	case screenSentiment:
		return withNavigation(appItems("sentiment", stageDefault(m.stage, "sentiment")))
	case screenSubnetcalc:
		return withNavigation(appItems("subnetcalc", stageDefault(m.stage, "subnetcalc")))
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
	var stages []string
	switch m.stage {
	case "500":
		stages = []string{"600", "900", "950-local-idp"}
	case "600":
		stages = []string{"700", "800", "900", "950-local-idp"}
	case "700":
		stages = []string{"800", "900", "950-local-idp"}
	case "800":
		stages = []string{"900", "950-local-idp"}
	case "900":
		stages = []string{"950-local-idp"}
	}
	if m.target != "kind" {
		stages = removeStage(stages, "950-local-idp")
	}
	items := make([]menuItem, 0, len(stages))
	for _, stage := range stages {
		items = append(items, menuItem{
			Label: fmt.Sprintf("%s apply", stageDisplay(stage)),
			Value: "next:" + stage,
		})
	}
	return items
}

func removeStage(stages []string, remove string) []string {
	kept := stages[:0]
	for _, stage := range stages {
		if stage != remove {
			kept = append(kept, stage)
		}
	}
	return kept
}

func stageDisplay(stage string) string {
	if stage == "950-local-idp" {
		return "950"
	}
	return stage
}

func stageShortcutValue(shortcut rune, target string) (string, bool) {
	switch shortcut {
	case '1':
		return "100", true
	case '2':
		return "200", true
	case '3':
		return "300", true
	case '4':
		return "400", true
	case '5':
		return "500", true
	case '6':
		return "600", true
	case '7':
		return "700", true
	case '8':
		return "800", true
	case '9':
		return "900", true
	case '0':
		return "950-local-idp", target == "kind"
	default:
		return "", false
	}
}

func (m Model) selectNext(value string) (tea.Model, tea.Cmd) {
	stage := strings.TrimPrefix(value, "next:")
	m.stage = stage
	m.stageLabel = stageDisplay(stage)
	m.action = "apply"
	m.sentiment = ""
	m.subnetcalc = ""
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

func withNavigation(items []menuItem) []menuItem {
	return append(items,
		menuItem{Label: "Back", Value: "back"},
		menuItem{Label: "Quit", Value: "quit"},
	)
}

func appItems(app string, enabled bool) []menuItem {
	if enabled {
		return []menuItem{
			{Label: fmt.Sprintf("Enable %s (stage default)", app), Value: ""},
			{Label: fmt.Sprintf("Disable %s", app), Value: app + "=off"},
		}
	}
	return []menuItem{
		{Label: fmt.Sprintf("Disable %s (stage default)", app), Value: ""},
		{Label: fmt.Sprintf("Enable %s", app), Value: app + "=on"},
	}
}

func stageDefault(stage, app string) bool {
	if stage == "950-local-idp" {
		return app == "sentiment"
	}
	switch stage {
	case "700", "800", "900":
		return true
	default:
		return false
	}
}

func (m Model) hasAppToggles() bool {
	return stageHasAppToggles(m.stage)
}

func stageHasAppToggles(stage string) bool {
	switch stage {
	case "700", "800", "900", "950-local-idp":
		return true
	default:
		return false
	}
}

func (m Model) workflowArgs(subcommand string) []string {
	args := []string{subcommand, "--execute"}
	if subcommand == "preview" {
		args = append(args, "--output", "json")
	}
	args = append(args, "--target", m.target, "--stage", m.stage, "--action", m.action)
	if m.sentiment != "" {
		args = append(args, "--app", m.sentiment)
	}
	if m.subnetcalc != "" {
		args = append(args, "--app", m.subnetcalc)
	}
	if m.action == "apply" || m.action == "reset" || m.action == "state-reset" {
		args = append(args, "--auto-approve")
	}
	return args
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
	subtitle := lipgloss.NewStyle().Foreground(lipgloss.Color("245")).Render("Choose a target, stage, action, and app toggles.")
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
	if m.target != "" {
		parts = append(parts, m.target)
	}
	if m.stage != "" && m.action != "reset" && m.action != "state-reset" {
		parts = append(parts, m.stage)
	}
	if m.action != "" {
		parts = append(parts, m.action)
	}
	return strings.Join(parts, " / ")
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
			return "Pick the local runtime target before choosing a stage."
		}
	case screenStage:
		return m.stageHint(item)
	case screenAction:
		return m.actionHint(item)
	case screenSentiment, screenSubnetcalc:
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
	case "950-local-idp":
		return "0 selects 950 local-idp: kind-only local identity provider finish stage."
	case "reset":
		return "r resets the selected target through the workflow script."
	case "state-reset":
		return "t resets Terraform state for the selected target."
	default:
		return "Stages 100-600 hide app toggles because apps are not contained until stage 700."
	}
}

func (m Model) actionHint(item menuItem) string {
	if !m.hasAppToggles() {
		return fmt.Sprintf("%s on stage %s skips app toggles; app choices appear at stages 700, 800, 900, and kind 950.", item.Label, stageDisplay(m.stage))
	}
	return fmt.Sprintf("%s on stage %s can include app toggle overrides before preview.", item.Label, stageDisplay(m.stage))
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
