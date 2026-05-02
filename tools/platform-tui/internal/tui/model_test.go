package tui

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/muesli/termenv"
)

func key(s string) tea.KeyMsg {
	if s == "enter" {
		return tea.KeyMsg{Type: tea.KeyEnter}
	}
	if s == "esc" {
		return tea.KeyMsg{Type: tea.KeyEsc}
	}
	if s == "ctrl+c" {
		return tea.KeyMsg{Type: tea.KeyCtrlC}
	}
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)}
}

func choose(m Model, t *testing.T, label string) Model {
	t.Helper()
	next, _ := selectLabel(m, t, label)
	return next
}

func selectLabel(m Model, t *testing.T, label string) (Model, tea.Cmd) {
	t.Helper()
	for i, item := range m.items() {
		if item.Label == label {
			m.cursor = i
			selected, cmd := m.Update(key("enter"))
			return selected.(Model), cmd
		}
	}
	t.Fatalf("option %q not found in %v", label, m.items())
	return m, nil
}

func drainRun(m Model, cmd tea.Cmd, t *testing.T) Model {
	t.Helper()
	for i := 0; i < 20 && cmd != nil; i++ {
		next, nextCmd := m.Update(cmd())
		m = next.(Model)
		cmd = nextCmd
		if !m.running {
			return m
		}
	}
	t.Fatalf("run did not finish; view: %q", m.View())
	return m
}

func TestQQuitsImmediately(t *testing.T) {
	m := New(Config{})
	_, cmd := m.Update(key("q"))
	if cmd == nil {
		t.Fatalf("expected quit command")
	}
	if _, ok := cmd().(tea.QuitMsg); !ok {
		t.Fatalf("expected tea.QuitMsg, got %T", cmd())
	}
}

func TestEscBacksOutOneScreen(t *testing.T) {
	m := New(Config{})
	m = choose(m, t, "kind")
	if m.screen != screenStage {
		t.Fatalf("expected stage screen, got %v", m.screen)
	}

	next, _ := m.Update(key("esc"))
	m = next.(Model)
	if m.screen != screenTarget {
		t.Fatalf("expected target screen after esc, got %v", m.screen)
	}
}

func TestResetBuildsCommandWithoutStageOrAppToggles(t *testing.T) {
	m := New(Config{})
	m = choose(m, t, "kind")
	m = choose(m, t, "Reset target")

	if m.screen != screenPreview {
		t.Fatalf("expected preview screen, got %v", m.screen)
	}
	wantPreview := []string{"preview", "--execute", "--output", "json", "--target", "kind", "--stage", "100", "--action", "reset", "--auto-approve"}
	if !reflect.DeepEqual(m.workflowArgs("preview"), wantPreview) {
		t.Fatalf("preview args\nwant %#v\n got %#v", wantPreview, m.workflowArgs("preview"))
	}
	wantApply := []string{"apply", "--execute", "--target", "kind", "--stage", "100", "--action", "reset", "--auto-approve"}
	if !reflect.DeepEqual(m.workflowArgs("apply"), wantApply) {
		t.Fatalf("apply args\nwant %#v\n got %#v", wantApply, m.workflowArgs("apply"))
	}
}

func TestStateResetBuildsCommandWithoutStageOrAppToggles(t *testing.T) {
	m := New(Config{})
	m = choose(m, t, "kind")
	m = choose(m, t, "Terraform state reset")

	if m.screen != screenPreview {
		t.Fatalf("expected preview screen, got %v", m.screen)
	}
	wantPreview := []string{"preview", "--execute", "--output", "json", "--target", "kind", "--stage", "100", "--action", "state-reset", "--auto-approve"}
	if !reflect.DeepEqual(m.workflowArgs("preview"), wantPreview) {
		t.Fatalf("preview args\nwant %#v\n got %#v", wantPreview, m.workflowArgs("preview"))
	}
	wantApply := []string{"apply", "--execute", "--target", "kind", "--stage", "100", "--action", "state-reset", "--auto-approve"}
	if !reflect.DeepEqual(m.workflowArgs("apply"), wantApply) {
		t.Fatalf("apply args\nwant %#v\n got %#v", wantApply, m.workflowArgs("apply"))
	}
}

func TestKindOnlyLocalIDPStage(t *testing.T) {
	m := New(Config{})
	m = choose(m, t, "kind")
	if !hasLabel(m.items(), "950 local-idp") {
		t.Fatalf("kind should expose local IDP stage")
	}

	m = New(Config{})
	m = choose(m, t, "lima")
	if hasLabel(m.items(), "950 local-idp") {
		t.Fatalf("lima must not expose local IDP stage")
	}
}

func TestApplyGetsAutoApproveAndPlanDoesNot(t *testing.T) {
	m := New(Config{})
	m = choose(m, t, "kind")
	m = choose(m, t, "700 app repos")
	m = choose(m, t, "apply")
	m = choose(m, t, "Disable sentiment")
	m = choose(m, t, "Enable subnetcalc (stage default)")
	if got := m.workflowArgs("preview"); !contains(got, "--auto-approve") {
		t.Fatalf("apply preview should include auto approve: %#v", got)
	}

	m = New(Config{})
	m = choose(m, t, "kind")
	m = choose(m, t, "700 app repos")
	m = choose(m, t, "plan")
	m = choose(m, t, "Disable sentiment")
	m = choose(m, t, "Enable subnetcalc (stage default)")
	if got := m.workflowArgs("preview"); contains(got, "--auto-approve") {
		t.Fatalf("plan preview should not include auto approve: %#v", got)
	}
}

func TestAppTogglesOnlyAppearForAppStages(t *testing.T) {
	for _, stage := range []string{
		"100 cluster",
		"200 cilium",
		"300 hubble",
		"400 argocd",
		"500 gitea",
		"600 policies",
	} {
		m := New(Config{})
		m = choose(m, t, "kind")
		m = choose(m, t, stage)
		next, cmd := selectLabel(m, t, "apply")
		m = next
		if m.screen != screenPreview {
			t.Fatalf("%s should skip app toggles and go to preview, got screen %v", stage, m.screen)
		}
		if cmd == nil {
			t.Fatalf("%s apply should load preview immediately", stage)
		}
		if hasLabel(m.items(), "Enable sentiment (stage default)") || hasLabel(m.items(), "Enable sentiment") {
			t.Fatalf("%s should not expose sentiment toggles, got %#v", stage, m.items())
		}
	}

	m := New(Config{})
	m = choose(m, t, "kind")
	m = choose(m, t, "700 app repos")
	m = choose(m, t, "apply")
	if m.screen != screenSentiment {
		t.Fatalf("stage 700 should still offer app toggles, got screen %v", m.screen)
	}
	if !hasLabel(m.items(), "Enable sentiment (stage default)") {
		t.Fatalf("stage 700 should expose sentiment toggle, got %#v", m.items())
	}
}

func TestViewHasSingleHeaderAndFooterHints(t *testing.T) {
	m := New(Config{})
	view := m.View()
	if count := stringCount(view, "Platform TUI"); count != 1 {
		t.Fatalf("expected one header, got %d in %q", count, view)
	}
	if !containsString(view, "q quit") || !containsString(view, "esc back") {
		t.Fatalf("expected footer hints, got %q", view)
	}
}

func TestIntermediateScreensHaveExplicitBackAndQuit(t *testing.T) {
	m := New(Config{})
	m = choose(m, t, "kind")
	m = choose(m, t, "700 app repos")
	m = choose(m, t, "plan")
	m = choose(m, t, "Enable sentiment (stage default)")

	if m.screen != screenSubnetcalc {
		t.Fatalf("expected subnetcalc screen, got %v", m.screen)
	}
	if !hasLabel(m.items(), "Back") {
		t.Fatalf("expected explicit Back item on subnetcalc screen, got %#v", m.items())
	}
	if !hasLabel(m.items(), "Quit") {
		t.Fatalf("expected explicit Quit item on subnetcalc screen, got %#v", m.items())
	}

	m = choose(m, t, "Back")
	if m.screen != screenSentiment {
		t.Fatalf("expected Back item to move to sentiment screen, got %v", m.screen)
	}

	_, cmd := selectLabel(m, t, "Quit")
	if cmd == nil {
		t.Fatalf("expected Quit item to return command")
	}
	if _, ok := cmd().(tea.QuitMsg); !ok {
		t.Fatalf("expected Quit item to return tea.QuitMsg, got %T", cmd())
	}
}

func TestPreviewCommandIsStyled(t *testing.T) {
	lipgloss.SetColorProfile(termenv.ANSI256)
	t.Cleanup(func() {
		lipgloss.SetColorProfile(termenv.Ascii)
	})

	m := New(Config{})
	m.screen = screenPreview
	m.previewCommand = "make -C kubernetes/kind 100 plan"

	line := lineContaining(m.View(), "Command: make -C kubernetes/kind 100 plan")
	if line == "" {
		t.Fatalf("expected command line in view, got %q", m.View())
	}
	if !containsString(line, "\x1b[1m") && !containsString(line, "\x1b[1;") {
		t.Fatalf("expected command line to be bold, got %q", line)
	}
	if !containsString(line, "38;5;") {
		t.Fatalf("expected command line to have a foreground colour, got %q", line)
	}
}

func TestPreviewFailureShowsCommandOutput(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "workflow.sh")
	if err := os.WriteFile(script, []byte(`#!/usr/bin/env bash
set -euo pipefail
echo "kind-local exists, but terraform state lock remains" >&2
echo "Lock: OperationTypeApply; tester; now" >&2
exit 2
`), 0o755); err != nil {
		t.Fatalf("write workflow stub: %v", err)
	}

	m := New(Config{WorkflowScript: script})
	m = choose(m, t, "kind")
	m = choose(m, t, "700 app repos")
	m = choose(m, t, "plan")
	m = choose(m, t, "Enable sentiment (stage default)")

	next, cmd := m.Update(key("enter"))
	m = next.(Model)
	if cmd == nil {
		t.Fatalf("expected preview command")
	}
	next, _ = m.Update(cmd())
	m = next.(Model)

	view := m.View()
	if containsString(view, "exit status 2\n\n➜ Run") {
		t.Fatalf("view only showed exit status: %q", view)
	}
	if !containsString(view, "Preview failed") {
		t.Fatalf("expected preview failure label, got %q", view)
	}
	if !containsString(view, "kind-local exists, but terraform state lock remains") {
		t.Fatalf("expected underlying stderr in view, got %q", view)
	}
	if !containsString(view, "Lock: OperationTypeApply; tester; now") {
		t.Fatalf("expected lock details in view, got %q", view)
	}
}

func TestRunFailureShowsCommandOutput(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "workflow.sh")
	if err := os.WriteFile(script, []byte(`#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  preview)
    printf '{"command":"make -C kubernetes/kind 100 plan"}\n'
    ;;
  apply)
    echo "kind-local exists, but terraform state lock remains" >&2
    echo "Lock: OperationTypeApply; tester; now" >&2
    exit 2
    ;;
esac
`), 0o755); err != nil {
		t.Fatalf("write workflow stub: %v", err)
	}

	m := New(Config{WorkflowScript: script})
	m = choose(m, t, "kind")
	m = choose(m, t, "700 app repos")
	m = choose(m, t, "plan")
	m = choose(m, t, "Enable sentiment (stage default)")

	next, cmd := m.Update(key("enter"))
	m = next.(Model)
	if cmd == nil {
		t.Fatalf("expected preview command")
	}
	next, _ = m.Update(cmd())
	m = next.(Model)
	if m.previewCommand != "make -C kubernetes/kind 100 plan" {
		t.Fatalf("expected preview command, got %q", m.previewCommand)
	}

	next, cmd = m.Update(key("enter"))
	m = next.(Model)
	if cmd == nil {
		t.Fatalf("expected run command")
	}
	m = drainRun(m, cmd, t)

	view := m.View()
	if containsString(view, "exit status 2\n\n➜ Run") {
		t.Fatalf("view only showed exit status: %q", view)
	}
	if !containsString(view, "Run failed") {
		t.Fatalf("expected run failure label, got %q", view)
	}
	if !containsString(view, "kind-local exists, but terraform state lock remains") {
		t.Fatalf("expected underlying stderr in view, got %q", view)
	}
	if !containsString(view, "Lock: OperationTypeApply; tester; now") {
		t.Fatalf("expected lock details in view, got %q", view)
	}
}

func TestRunOutputViewportScrollsAndFollows(t *testing.T) {
	m := New(Config{})
	m.screen = screenPreview
	m.Update(tea.WindowSizeMsg{Width: 90, Height: 24})
	m.autoFollow = true

	var cmd tea.Cmd
	for i := 1; i <= 40; i++ {
		next, nextCmd := m.Update(runOutputMsg{Text: "line"})
		m = next.(Model)
		cmd = nextCmd
	}
	if cmd == nil {
		t.Fatalf("expected wait command after output chunk")
	}
	if !m.outputViewport.AtBottom() {
		t.Fatalf("expected viewport to follow output bottom")
	}

	before := m.outputViewport.YOffset
	next, _ := m.Update(key("pgup"))
	m = next.(Model)
	if !m.outputViewport.AtTop() && m.outputViewport.YOffset >= before {
		t.Fatalf("expected pgup to scroll output up, before=%d after=%d", before, m.outputViewport.YOffset)
	}
	if m.autoFollow {
		t.Fatalf("expected manual scroll up to disable auto-follow")
	}

	offset := m.outputViewport.YOffset
	next, _ = m.Update(runOutputMsg{Text: "new bottom line"})
	m = next.(Model)
	if m.outputViewport.YOffset != offset {
		t.Fatalf("expected viewport to stay put while auto-follow is disabled")
	}

	next, _ = m.Update(key("end"))
	m = next.(Model)
	if !m.outputViewport.AtBottom() {
		t.Fatalf("expected end to jump to bottom")
	}
	if !m.autoFollow {
		t.Fatalf("expected end to re-enable auto-follow")
	}
	if !containsString(m.View(), "pgup/pgdn scroll") {
		t.Fatalf("expected scroll help in preview output view, got %q", m.View())
	}
}

func TestSuccessfulRunMovesFocusToBack(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "workflow.sh")
	if err := os.WriteFile(script, []byte(`#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  preview)
    printf '{"command":"make -C kubernetes/kind reset AUTO_APPROVE=1"}\n'
    ;;
  apply)
    echo "OK   Deleted kind-local"
    echo "OK   Done"
    ;;
esac
`), 0o755); err != nil {
		t.Fatalf("write workflow stub: %v", err)
	}

	m := New(Config{WorkflowScript: script})
	m = choose(m, t, "kind")
	next, cmd := selectLabel(m, t, "Reset target")
	m = next
	if cmd == nil {
		t.Fatalf("expected preview command")
	}
	nextModel, _ := m.Update(cmd())
	m = nextModel.(Model)

	next, cmd = selectLabel(m, t, "Run")
	m = next
	if cmd == nil {
		t.Fatalf("expected run command")
	}
	m = drainRun(m, cmd, t)

	items := m.items()
	if got := items[m.cursor].Label; got != "Back" {
		t.Fatalf("expected focus to move to Back after successful reset, got %q in view %q", got, m.View())
	}
	if !containsString(m.View(), "OK   Done") {
		t.Fatalf("expected successful run output to remain visible, got %q", m.View())
	}
}

func TestSuccessfulApplyOffersOpinionatedNextStages(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "workflow.sh")
	if err := os.WriteFile(script, []byte(`#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  preview)
    printf '{"command":"preview %s %s"}\n' "$6" "$8"
    ;;
  apply)
    echo "OK   stage complete"
    ;;
esac
`), 0o755); err != nil {
		t.Fatalf("write workflow stub: %v", err)
	}

	m := New(Config{WorkflowScript: script})
	m = choose(m, t, "kind")
	m = choose(m, t, "500 gitea")
	next, cmd := selectLabel(m, t, "apply")
	m = next
	if cmd == nil {
		t.Fatalf("expected preview command")
	}
	nextModel, _ := m.Update(cmd())
	m = nextModel.(Model)

	next, cmd = selectLabel(m, t, "Run")
	m = next
	m = drainRun(m, cmd, t)

	for _, label := range []string{"600 apply", "900 apply", "950 apply"} {
		if !hasLabel(m.items(), label) {
			t.Fatalf("expected next option %q after successful 500 apply, got %#v", label, m.items())
		}
	}
	if got := m.items()[m.cursor].Label; got != "Back" {
		t.Fatalf("expected Back to keep focus after success, got %q", got)
	}

	next, cmd = selectLabel(m, t, "900 apply")
	m = next
	if cmd == nil {
		t.Fatalf("expected next option to load preview")
	}
	if m.stage != "900" || m.action != "apply" {
		t.Fatalf("expected next option to prepare 900 apply, got stage=%q action=%q", m.stage, m.action)
	}
	if m.runOutput != "" || m.runSucceeded {
		t.Fatalf("expected next option to clear prior run state")
	}
}

func TestSuccessful600ApplyOffersIntermediateAndJumpStages(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "workflow.sh")
	if err := os.WriteFile(script, []byte(`#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  preview)
    printf '{"command":"preview %s %s"}\n' "$6" "$8"
    ;;
  apply)
    echo "OK   stage complete"
    ;;
esac
`), 0o755); err != nil {
		t.Fatalf("write workflow stub: %v", err)
	}

	m := New(Config{WorkflowScript: script})
	m = choose(m, t, "kind")
	m = choose(m, t, "600 policies")
	next, cmd := selectLabel(m, t, "apply")
	m = next
	if cmd == nil {
		t.Fatalf("expected preview command")
	}
	nextModel, _ := m.Update(cmd())
	m = nextModel.(Model)

	next, cmd = selectLabel(m, t, "Run")
	m = next
	m = drainRun(m, cmd, t)

	for _, label := range []string{"700 apply", "800 apply", "900 apply", "950 apply"} {
		if !hasLabel(m.items(), label) {
			t.Fatalf("expected next option %q after successful 600 apply, got %#v", label, m.items())
		}
	}
}

func TestRunShowsImmediateRunningState(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "workflow.sh")
	if err := os.WriteFile(script, []byte(`#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  preview)
    printf '{"command":"make -C kubernetes/kind 100 plan"}\n'
    ;;
  apply)
    sleep 5
    ;;
esac
`), 0o755); err != nil {
		t.Fatalf("write workflow stub: %v", err)
	}

	m := New(Config{WorkflowScript: script})
	m = choose(m, t, "kind")
	m = choose(m, t, "700 app repos")
	m = choose(m, t, "plan")
	m = choose(m, t, "Enable sentiment (stage default)")

	next, cmd := m.Update(key("enter"))
	m = next.(Model)
	next, _ = m.Update(cmd())
	m = next.(Model)

	next, cmd = m.Update(key("enter"))
	m = next.(Model)
	if cmd == nil {
		t.Fatalf("expected run command")
	}
	if !m.running {
		t.Fatalf("expected model to enter running state before command finishes")
	}
	if !containsString(m.View(), "Running workflow") {
		t.Fatalf("expected immediate running feedback, got %q", m.View())
	}

	done := make(chan tea.Msg, 1)
	go func() {
		done <- cmd()
	}()
	select {
	case <-done:
		t.Fatalf("run command returned before long-running workflow completed")
	case <-time.After(100 * time.Millisecond):
	}
}

func TestRunOutputDoesNotLeakWhenBackingOutOfPreview(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "workflow.sh")
	if err := os.WriteFile(script, []byte(`#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  preview)
    printf '{"command":"make -C kubernetes/kind 100 plan"}\n'
    ;;
  apply)
    echo "Target: kind (kubernetes/kind)"
    echo "kind-local exists, but terraform state lock remains" >&2
    exit 2
    ;;
esac
`), 0o755); err != nil {
		t.Fatalf("write workflow stub: %v", err)
	}

	m := New(Config{WorkflowScript: script})
	m = choose(m, t, "kind")
	m = choose(m, t, "700 app repos")
	m = choose(m, t, "plan")
	m = choose(m, t, "Enable sentiment (stage default)")

	next, cmd := m.Update(key("enter"))
	m = next.(Model)
	next, _ = m.Update(cmd())
	m = next.(Model)

	next, cmd = m.Update(key("enter"))
	m = next.(Model)
	m = drainRun(m, cmd, t)
	if !containsString(m.View(), "kind-local exists, but terraform state lock remains") {
		t.Fatalf("expected failed run output before backing out, got %q", m.View())
	}

	next, _ = m.Update(key("esc"))
	m = next.(Model)
	if m.screen != screenSubnetcalc {
		t.Fatalf("expected subnetcalc screen after backing out, got %v", m.screen)
	}
	view := m.View()
	if containsString(view, "kind-local exists, but terraform state lock remains") {
		t.Fatalf("run output leaked into prior screen: %q", view)
	}
	if containsString(view, "Target: kind (kubernetes/kind)") {
		t.Fatalf("run output leaked into prior screen: %q", view)
	}
}
