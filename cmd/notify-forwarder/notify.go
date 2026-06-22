package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

func SendWithRetry(ctx context.Context, config Config, snapshot InputSnapshot) (State, error) {
	startedAt := time.Now()
	deadline := startedAt.Add(config.RetryMaxElapsed())
	interval := config.RetryInitialInterval()
	attempt := 1

	for {
		err := SendNotification(ctx, config, snapshot.Notification)
		if err == nil {
			log.Printf("notification sent: updated_at=%s body=%q", snapshot.UpdatedAt, snapshot.Notification.Body)
			return State{
				LastEventKey:  snapshot.EventKey,
				LastUpdatedAt: snapshot.UpdatedAt,
				LastSentAt:    time.Now().Format(time.RFC3339Nano),
			}, nil
		}

		if ctx.Err() != nil {
			return State{}, ctx.Err()
		}
		if time.Now().After(deadline) {
			return State{}, fmt.Errorf("retry deadline exceeded after %s: %w", config.RetryMaxElapsed(), err)
		}

		log.Printf("notification send attempt %d failed: %v", attempt, err)
		sleep := interval
		if remaining := time.Until(deadline); sleep > remaining {
			sleep = remaining
		}

		select {
		case <-ctx.Done():
			return State{}, ctx.Err()
		case <-time.After(sleep):
		}

		if interval < config.RetryMaxInterval() {
			interval *= 2
			if interval > config.RetryMaxInterval() {
				interval = config.RetryMaxInterval()
			}
		}
		attempt++
	}
}

func SendNotification(ctx context.Context, config Config, notification NotifyRequest) error {
	var body bytes.Buffer
	if err := json.NewEncoder(&body).Encode(notification); err != nil {
		return fmt.Errorf("encode request: %w", err)
	}

	requestCtx, cancel := context.WithTimeout(ctx, config.RequestTimeout())
	defer cancel()

	request, err := http.NewRequestWithContext(requestCtx, http.MethodPost, config.NotifyURL, &body)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	request.Header.Set("Content-Type", "application/json; charset=utf-8")

	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return fmt.Errorf("post notify: %w", err)
	}
	defer response.Body.Close()

	if response.StatusCode < 200 || response.StatusCode >= 300 {
		responseBody, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
		return fmt.Errorf("post notify returned %s: %s", response.Status, string(responseBody))
	}

	return nil
}
