package app

import (
	"encoding/csv"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type store struct {
	path string
}

func newStore(cfg Config) store {
	path := cfg.CSVPath
	if path == "" {
		dataDir := cfg.DataDir
		if dataDir == "" {
			dataDir = "/tmp/sentiment"
		}
		path = filepath.Join(dataDir, "comments.csv")
	}
	return store{path: path}
}

func (s store) ensure() error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0o755); err != nil {
		return err
	}
	if _, err := os.Stat(s.path); err == nil {
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return err
	}
	file, err := os.Create(s.path)
	if err != nil {
		return err
	}
	defer file.Close()
	_, err = file.WriteString("id,timestamp,text,label,confidence,latency_ms\n")
	return err
}

func (s store) append(comment Comment) error {
	if err := s.ensure(); err != nil {
		return err
	}
	file, err := os.OpenFile(s.path, os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer file.Close()
	writer := csv.NewWriter(file)
	defer writer.Flush()
	return writer.Write([]string{
		comment.ID,
		comment.Timestamp,
		comment.Text,
		string(comment.Label),
		fmt.Sprintf("%.2f", comment.Confidence),
		strconv.FormatInt(comment.LatencyMS, 10),
	})
}

func (s store) list(limit int) ([]Comment, error) {
	if err := s.ensure(); err != nil {
		return nil, err
	}
	file, err := os.Open(s.path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	reader := csv.NewReader(file)
	reader.FieldsPerRecord = -1
	rows, err := reader.ReadAll()
	if err != nil {
		return nil, err
	}
	comments := []Comment{}
	for i := len(rows) - 1; i >= 1; i-- {
		comment, ok := parseCommentRow(rows[i], i)
		if !ok {
			continue
		}
		comments = append(comments, comment)
		if limit > 0 && len(comments) >= limit {
			break
		}
	}
	return comments, nil
}

func parseCommentRow(row []string, index int) (Comment, bool) {
	switch {
	case len(row) == 5:
		confidence, _ := strconv.ParseFloat(row[3], 64)
		latency, _ := strconv.ParseInt(row[4], 10, 64)
		return Comment{
			ID:         fmt.Sprintf("legacy-comment-%d", index),
			Timestamp:  row[0],
			Text:       row[1],
			Label:      Label(row[2]),
			Confidence: confidence,
			LatencyMS:  latency,
		}, true
	case len(row) >= 6:
		labelIndex := len(row) - 3
		confidence, _ := strconv.ParseFloat(row[len(row)-2], 64)
		latency, _ := strconv.ParseInt(row[len(row)-1], 10, 64)
		return Comment{
			ID:         row[0],
			Timestamp:  row[1],
			Text:       strings.Join(row[2:labelIndex], ","),
			Label:      Label(row[labelIndex]),
			Confidence: confidence,
			LatencyMS:  latency,
		}, true
	default:
		return Comment{}, false
	}
}

func newComment(text string, result classifyResponse) Comment {
	now := time.Now().UTC()
	return Comment{
		ID:         fmt.Sprintf("comment-%d", now.UnixNano()),
		Timestamp:  now.Format(time.RFC3339Nano),
		Text:       text,
		Label:      result.Label,
		Confidence: result.Confidence,
		LatencyMS:  result.LatencyMS,
	}
}
