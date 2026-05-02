package main

import (
	"flag"
	"fmt"
	"os"
	"os/exec"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/nickromney/platform/tools/platform-tui/internal/tui"
)

func main() {
	execute := flag.Bool("execute", false, "run the interactive TUI")
	repoRootFlag := flag.String("repo-root", "", "platform repository root")
	flag.Bool("dry-run", false, "preview launching the TUI")
	flag.Parse()

	if !*execute {
		fmt.Println("would open the local runtime chooser")
		return
	}

	repoRoot := *repoRootFlag
	if repoRoot == "" {
		var err error
		repoRoot, err = os.Getwd()
		if err != nil {
			fmt.Fprintf(os.Stderr, "platform-tui: %v\n", err)
			os.Exit(1)
		}
	}

	statusScript := getenv("PLATFORM_STATUS_SCRIPT", "scripts/platform-status.sh")
	workflowScript := getenv("PLATFORM_WORKFLOW_SCRIPT", "scripts/platform-workflow.sh")

	if !isTerminal(os.Stdin) || !isTerminal(os.Stdout) {
		cmd := exec.Command(statusScript, "--execute", "--output", "text")
		cmd.Dir = repoRoot
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
		if err := cmd.Run(); err != nil {
			fmt.Fprintf(os.Stderr, "platform-tui: %v\n", err)
			os.Exit(1)
		}
		return
	}

	model := tui.New(tui.Config{
		RepoRoot:       repoRoot,
		WorkflowScript: workflowScript,
		StatusScript:   statusScript,
	})
	if _, err := tea.NewProgram(model, tea.WithAltScreen(), tea.WithMouseCellMotion()).Run(); err != nil {
		fmt.Fprintf(os.Stderr, "platform-tui: %v\n", err)
		os.Exit(1)
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func isTerminal(file *os.File) bool {
	info, err := file.Stat()
	if err != nil {
		return false
	}
	return (info.Mode() & os.ModeCharDevice) != 0
}
