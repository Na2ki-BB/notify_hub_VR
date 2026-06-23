package main

import (
	"testing"
	"time"
)

func TestMaxNotificationAgeDefaultsToThirtySeconds(t *testing.T) {
	if got := (Config{}).MaxNotificationAge(); got != 30*time.Second {
		t.Fatalf("MaxNotificationAge mismatch: %s", got)
	}
}

func TestMaxNotificationAgeCanBeDisabled(t *testing.T) {
	maxAge := 0
	config := Config{MaxNotificationAgeMS: &maxAge}

	if got := config.MaxNotificationAge(); got != 0 {
		t.Fatalf("MaxNotificationAge should be disabled, got %s", got)
	}
}
