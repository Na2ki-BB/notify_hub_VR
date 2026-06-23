package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestSendNotificationPostsUTF8JSON(t *testing.T) {
	var received NotifyRequest
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Content-Type"); got != "application/json; charset=utf-8" {
			t.Fatalf("Content-Type mismatch: %q", got)
		}
		if err := json.NewDecoder(r.Body).Decode(&received); err != nil {
			t.Fatalf("decode request: %v", err)
		}
		w.WriteHeader(http.StatusAccepted)
	}))
	defer server.Close()

	config := Config{
		NotifyURL:        server.URL,
		RequestTimeoutMS: 5000,
	}
	notification := NotifyRequest{
		Title:      "Notify Hub",
		Body:       "日本語テスト",
		Level:      "info",
		DurationMS: 5000,
	}

	if err := SendNotification(context.Background(), config, notification); err != nil {
		t.Fatalf("SendNotification returned error: %v", err)
	}
	if received.Body != "日本語テスト" {
		t.Fatalf("Body mismatch: %q", received.Body)
	}
}

func TestSendNotificationReportsHTTPFailure(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Error(w, "not ready", http.StatusServiceUnavailable)
	}))
	defer server.Close()

	config := Config{
		NotifyURL:        server.URL,
		RequestTimeoutMS: 5000,
	}
	err := SendNotification(context.Background(), config, NotifyRequest{Body: "hello"})
	if err == nil {
		t.Fatal("SendNotification should fail for non-2xx status")
	}
	if !strings.Contains(err.Error(), "503") {
		t.Fatalf("error should include HTTP status: %v", err)
	}
}

func TestClassifyRetryUsesShortRetryForServiceUnavailable(t *testing.T) {
	err := &HTTPStatusError{
		StatusCode: http.StatusServiceUnavailable,
		Status:     "503 Service Unavailable",
		Body:       "renderer unavailable",
	}

	if got := classifyRetry(err); got != retryShortUnavailable {
		t.Fatalf("classifyRetry mismatch: %v", got)
	}
}

func TestClassifyRetryStopsForBadRequest(t *testing.T) {
	err := &HTTPStatusError{
		StatusCode: http.StatusBadRequest,
		Status:     "400 Bad Request",
		Body:       "bad payload",
	}

	if got := classifyRetry(err); got != retryStop {
		t.Fatalf("classifyRetry mismatch: %v", got)
	}
}

func TestSendWithRetryDropsStaleNotificationWithoutPosting(t *testing.T) {
	requests := 0
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
		w.WriteHeader(http.StatusAccepted)
	}))
	defer server.Close()

	maxAge := 1000
	config := Config{
		NotifyURL:              server.URL,
		RequestTimeoutMS:       1000,
		RetryInitialIntervalMS: 1000,
		RetryMaxIntervalMS:     1000,
		RetryMaxElapsedMS:      1000,
		MaxNotificationAgeMS:   &maxAge,
	}
	snapshot := InputSnapshot{
		EventKey:  "event-1",
		UpdatedAt: "2024-01-01T12:34:56",
		ModTime:   time.Now().Add(-2 * time.Second),
		Notification: NotifyRequest{
			Body: "old event",
		},
	}

	state, err := SendWithRetry(context.Background(), config, snapshot)
	if err != nil {
		t.Fatalf("SendWithRetry returned error: %v", err)
	}
	if requests != 0 {
		t.Fatalf("stale notification should not be posted, got %d requests", requests)
	}
	if state.LastEventKey != snapshot.EventKey {
		t.Fatalf("LastEventKey mismatch: %q", state.LastEventKey)
	}
	if state.LastSkippedAt == "" {
		t.Fatal("LastSkippedAt should be recorded")
	}
	if state.LastSkipReason != "stale" {
		t.Fatalf("LastSkipReason mismatch: %q", state.LastSkipReason)
	}
	if state.LastSentAt != "" {
		t.Fatalf("LastSentAt should be empty for skipped notifications: %q", state.LastSentAt)
	}
}
