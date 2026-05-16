package app

import (
	"encoding/csv"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
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
	rows, err := csv.NewReader(file).ReadAll()
	if err != nil {
		return nil, err
	}
	comments := []Comment{}
	for i := len(rows) - 1; i >= 1; i-- {
		row := rows[i]
		if len(row) < 6 {
			continue
		}
		confidence, _ := strconv.ParseFloat(row[4], 64)
		latency, _ := strconv.ParseInt(row[5], 10, 64)
		comments = append(comments, Comment{
			ID:         row[0],
			Timestamp:  row[1],
			Text:       row[2],
			Label:      Label(row[3]),
			Confidence: confidence,
			LatencyMS:  latency,
		})
		if limit > 0 && len(comments) >= limit {
			break
		}
	}
	return comments, nil
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
