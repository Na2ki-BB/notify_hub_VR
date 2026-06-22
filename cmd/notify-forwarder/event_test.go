package main

import "testing"

func TestBuildNotificationUsesThirdLineAsBody(t *testing.T) {
	config := Config{
		DefaultLevel:      "info",
		DefaultDurationMS: 5000,
	}
	source := SourceEvent{
		UpdatedAt: "2024-01-01T12:34:56",
		Lines: []string{
			"行1",
			"行2",
			"長めの行3",
			"行4",
		},
	}

	notification, err := BuildNotification(source, config)
	if err != nil {
		t.Fatalf("BuildNotification returned error: %v", err)
	}

	if notification.Title != "行1 / 行2 / 行4" {
		t.Fatalf("Title mismatch: %q", notification.Title)
	}
	if notification.Body != "長めの行3" {
		t.Fatalf("Body mismatch: %q", notification.Body)
	}
	if notification.Level != "info" {
		t.Fatalf("Level mismatch: %q", notification.Level)
	}
	if notification.DurationMS != 5000 {
		t.Fatalf("DurationMS mismatch: %d", notification.DurationMS)
	}
}

func TestBuildNotificationFallsBackWhenThirdLineIsEmpty(t *testing.T) {
	config := Config{
		DefaultLevel:      "warning",
		DefaultDurationMS: 7000,
	}
	source := SourceEvent{
		Lines: []string{" alpha ", "", " ", " beta "},
	}

	notification, err := BuildNotification(source, config)
	if err != nil {
		t.Fatalf("BuildNotification returned error: %v", err)
	}

	if notification.Title != "alpha / beta" {
		t.Fatalf("Title mismatch: %q", notification.Title)
	}
	if notification.Body != "alpha / beta" {
		t.Fatalf("Body mismatch: %q", notification.Body)
	}
	if notification.Level != "warning" {
		t.Fatalf("Level mismatch: %q", notification.Level)
	}
	if notification.DurationMS != 7000 {
		t.Fatalf("DurationMS mismatch: %d", notification.DurationMS)
	}
}
