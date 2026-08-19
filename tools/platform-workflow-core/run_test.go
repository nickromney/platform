package workflowcore

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

// Run drains stdout and stderr from two goroutines into one buffer and one
// handler. Before those shared writes were locked, `go test -race` reported a
// data race and lines could be lost or interleaved mid-write.
//
// The suite runs without -race (see mk/shared-go-module.mk), so this asserts
// the observable consequence instead: every line arrives exactly once, on both
// streams, with no torn writes.
func TestRunInterleavesBothStreamsWithoutLosingLines(t *testing.T) {
	const perStream = 400

	var lines []string
	output, err := Run(
		context.Background(),
		"",
		"/bin/sh",
		[]string{"-c", fmt.Sprintf("i=1; while [ $i -le %d ]; do echo out$i; echo err$i >&2; i=$((i+1)); done", perStream)},
		func(line string) { lines = append(lines, line) },
	)
	if err != nil {
		t.Fatalf("Run returned an error: %v", err)
	}

	if len(lines) != perStream*2 {
		t.Fatalf("handler saw %d lines, want %d", len(lines), perStream*2)
	}

	captured := strings.Split(output, "\n")
	if len(captured) != perStream*2 {
		t.Fatalf("captured %d lines, want %d", len(captured), perStream*2)
	}

	seen := make(map[string]int, perStream*2)
	for _, line := range captured {
		seen[line]++
	}
	for i := 1; i <= perStream; i++ {
		for _, want := range []string{fmt.Sprintf("out%d", i), fmt.Sprintf("err%d", i)} {
			if seen[want] != 1 {
				t.Fatalf("captured %q %d times, want exactly 1", want, seen[want])
			}
		}
	}
}

func TestRunReturnsCommandErrorWithOutput(t *testing.T) {
	output, err := Run(
		context.Background(),
		"",
		"/bin/sh",
		[]string{"-c", "echo before failing; exit 3"},
		nil,
	)
	if err == nil {
		t.Fatal("Run returned nil error for a command that exited 3")
	}
	if output != "before failing" {
		t.Fatalf("output = %q, want %q", output, "before failing")
	}
}
