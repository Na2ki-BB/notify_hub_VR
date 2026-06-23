package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"
)

type SourceEvent struct {
	UpdatedAt string   `json:"updated_at"`
	Lines     []string `json:"lines"`
}

type NotifyRequest struct {
	Title      string `json:"title,omitempty"`
	Body       string `json:"body"`
	Level      string `json:"level,omitempty"`
	DurationMS int    `json:"duration_ms,omitempty"`
	Sound      bool   `json:"sound,omitempty"`
}

type InputSnapshot struct {
	EventKey     string
	UpdatedAt    string
	ModTime      time.Time
	Source       SourceEvent
	Notification NotifyRequest
}

func ReadInputSnapshot(config Config) (InputSnapshot, error) {
	info, err := os.Stat(config.InputPath)
	if err != nil {
		return InputSnapshot{}, err
	}

	data, err := os.ReadFile(config.InputPath)
	if err != nil {
		return InputSnapshot{}, err
	}

	var source SourceEvent
	if err := json.Unmarshal(data, &source); err != nil {
		return InputSnapshot{}, fmt.Errorf("parse source JSON: %w", err)
	}

	notification, err := BuildNotification(source, config)
	if err != nil {
		return InputSnapshot{}, err
	}

	hash := sha256.Sum256(data)
	eventKey := fmt.Sprintf("mtime_ns=%d:size=%d:sha256=%s", info.ModTime().UnixNano(), info.Size(), hex.EncodeToString(hash[:]))

	return InputSnapshot{
		EventKey:     eventKey,
		UpdatedAt:    source.UpdatedAt,
		ModTime:      info.ModTime(),
		Source:       source,
		Notification: notification,
	}, nil
}

func (s InputSnapshot) StaleStatus(config Config, now time.Time) (bool, time.Duration, time.Duration) {
	maxAge := config.MaxNotificationAge()
	if maxAge <= 0 || s.ModTime.IsZero() {
		return false, 0, maxAge
	}

	age := now.Sub(s.ModTime)
	if age < 0 {
		return false, age, maxAge
	}
	return age > maxAge, age, maxAge
}

func BuildNotification(source SourceEvent, config Config) (NotifyRequest, error) {
	if len(source.Lines) == 0 {
		return NotifyRequest{}, fmt.Errorf("source lines must contain at least one line")
	}

	line := func(index int) string {
		if index < 0 || index >= len(source.Lines) {
			return ""
		}
		return strings.TrimSpace(source.Lines[index])
	}

	title := joinNonEmpty(" / ", line(0), line(1), line(3))
	body := line(2)
	if body == "" {
		body = joinNonEmpty(" / ", source.Lines...)
	}
	if strings.TrimSpace(body) == "" {
		return NotifyRequest{}, fmt.Errorf("source lines do not contain notification text")
	}

	return NotifyRequest{
		Title:      title,
		Body:       body,
		Level:      config.DefaultLevel,
		DurationMS: config.DefaultDurationMS,
	}, nil
}

func joinNonEmpty(separator string, values ...string) string {
	parts := make([]string, 0, len(values))
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed != "" {
			parts = append(parts, trimmed)
		}
	}
	return strings.Join(parts, separator)
}
