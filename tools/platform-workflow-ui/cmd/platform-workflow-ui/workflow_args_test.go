package main

import (
	"bufio"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// The workflow core takes a positional subcommand and a separate --action flag.
// The two vocabularies are disjoint apart from "apply", so passing an action
// where a subcommand belongs fails for every action except that one. This is
// the contract the browser UI got wrong: preview built its args with the
// literal "preview", but the run path passed selection.Action through.
//
// coreSubcommands is parsed from the core rather than hardcoded, so that adding
// a subcommand there cannot silently invalidate these tests.
func coreSubcommands(t *testing.T) []string {
	t.Helper()

	script := filepath.Join(repoRootForTest(t), "scripts", "platform-workflow.sh")
	file, err := os.Open(script)
	if err != nil {
		t.Fatalf("open workflow core: %v", err)
	}
	defer file.Close()

	// Matches the case arm listing the accepted subcommands, e.g.
	//   options|preview|apply|save-profile) ;;
	arm := regexp.MustCompile(`^\s*([a-z|-]*apply[a-z|-]*)\)\s*;;`)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		if m := arm.FindStringSubmatch(scanner.Text()); m != nil {
			return strings.Split(m[1], "|")
		}
	}
	t.Fatalf("could not find the subcommand case arm in %s", script)
	return nil
}

func repoRootForTest(t *testing.T) string {
	t.Helper()
	// cmd/platform-workflow-ui -> tools/platform-workflow-ui -> tools -> repo
	root, err := filepath.Abs(filepath.Join("..", "..", "..", ".."))
	if err != nil {
		t.Fatalf("resolve repo root: %v", err)
	}
	return root
}

// These drive the RUN PATH as jobStore.start builds it, not workflowArgs in
// isolation. An earlier version of this test called workflowArgs directly with
// the right constant and passed against the broken code, because the defect was
// never in workflowArgs -- it was in what the caller handed it.
func TestRunSubcommandIsAcceptedByTheCoreForEveryAction(t *testing.T) {
	accepted := coreSubcommands(t)
	acceptedSet := make(map[string]bool, len(accepted))
	for _, s := range accepted {
		acceptedSet[s] = true
	}

	// Every action the UI can present, including the one that collides.
	actions := []string{"plan", "apply", "status", "show-urls", "check-health", "check-security", "check-rbac", "readiness"}

	for _, action := range actions {
		t.Run(action, func(t *testing.T) {
			selection := workflowSelection{Variant: "kubernetes/kind", Stage: "100", Action: action}

			store := &jobStore{jobs: map[string]*workflowJob{}}
			job := store.start(repoRootForTest(t), selection, "", &historyStore{})

			// argv[0] is the script path; argv[1] is the positional subcommand.
			if len(job.Command) < 2 {
				t.Fatalf("command too short: %v", job.Command)
			}
			sub := job.Command[1]
			if !acceptedSet[sub] {
				t.Fatalf("subcommand %q is not accepted by the workflow core (accepts %v); the core dies with \"Unknown subcommand\"", sub, accepted)
			}
		})
	}
}

func TestActionTravelsAsAFlagNotAsTheSubcommand(t *testing.T) {
	selection := workflowSelection{Variant: "kubernetes/kind", Stage: "100", Action: "plan"}

	store := &jobStore{jobs: map[string]*workflowJob{}}
	job := store.start(repoRootForTest(t), selection, "", &historyStore{})
	args := job.Command

	if args[1] == "plan" {
		t.Fatal("action leaked into the subcommand position")
	}

	var sawActionFlag bool
	for i, a := range args {
		if a == "--action" && i+1 < len(args) && args[i+1] == "plan" {
			sawActionFlag = true
		}
	}
	if !sawActionFlag {
		t.Fatalf("expected --action plan in %v", args)
	}
}

func TestPreviewAndRunAgreeOnEverythingButTheSubcommand(t *testing.T) {
	selection := workflowSelection{Variant: "kubernetes/kind", Stage: "700", Action: "plan"}

	preview := workflowArgs(optionsPayload{}, selection, previewSubcommand, "--execute")
	run := workflowArgs(optionsPayload{}, selection, runSubcommand, "--execute")

	if len(preview) != len(run) {
		t.Fatalf("preview and run args differ in length: %v vs %v", preview, run)
	}
	for i := range preview {
		if i == 0 {
			continue // the subcommand is the one intended difference
		}
		if preview[i] != run[i] {
			t.Fatalf("preview and run diverge at index %d: %q vs %q", i, preview[i], run[i])
		}
	}
}
