package workflowcore

import (
	"bufio"
	"bytes"
	"context"
	"io"
	"os/exec"
	"strings"
)

type LineHandler func(line string)

func Run(ctx context.Context, cwd, script string, args []string, onLine LineHandler) (string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	cmd := exec.CommandContext(ctx, script, args...)
	if cwd != "" {
		cmd.Dir = cwd
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return "", err
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return "", err
	}
	if err := cmd.Start(); err != nil {
		return "", err
	}

	var captured bytes.Buffer
	send := func(text string) {
		text = strings.TrimRight(text, "\r\n")
		if text == "" {
			return
		}
		captured.WriteString(text)
		captured.WriteByte('\n')
		if onLine != nil {
			onLine(text)
		}
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

	waitErr := cmd.Wait()
	output := strings.TrimSpace(captured.String())
	return output, waitErr
}
