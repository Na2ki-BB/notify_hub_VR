package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

func SendWithRetry(ctx context.Context, config Config, snapshot InputSnapshot) (State, error) {
	startedAt := time.Now()
	deadline := startedAt.Add(config.RetryMaxElapsed())
	standardInterval := config.RetryInitialInterval()
	unavailableInterval := config.RetryUnavailableInitialInterval()
	attempt := 1

	for {
		if stale, age, maxAge := snapshot.StaleStatus(config, time.Now()); stale {
			now := time.Now()
			log.Printf("drop stale notification: updated_at=%s age=%s max_age=%s body=%q", snapshot.UpdatedAt, age.Round(time.Millisecond), maxAge, snapshot.Notification.Body)
			return State{
				LastEventKey:   snapshot.EventKey,
				LastUpdatedAt:  snapshot.UpdatedAt,
				LastSkippedAt:  now.Format(time.RFC3339Nano),
				LastSkipReason: "stale",
			}, nil
		}

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

		retryClass := classifyRetry(err)
		if retryClass == retryStop {
			return State{}, err
		}

		sleep := standardInterval
		if retryClass == retryShortUnavailable {
			sleep = unavailableInterval
		}
		if remaining := time.Until(deadline); sleep > remaining {
			sleep = remaining
		}

		log.Printf("notification send attempt %d failed; retrying in %s: %v", attempt, sleep, err)

		select {
		case <-ctx.Done():
			return State{}, ctx.Err()
		case <-time.After(sleep):
		}

		if retryClass == retryShortUnavailable {
			if unavailableInterval < config.RetryUnavailableMaxInterval() {
				unavailableInterval *= 2
				if unavailableInterval > config.RetryUnavailableMaxInterval() {
					unavailableInterval = config.RetryUnavailableMaxInterval()
				}
			}
		} else if standardInterval < config.RetryMaxInterval() {
			standardInterval *= 2
			if standardInterval > config.RetryMaxInterval() {
				standardInterval = config.RetryMaxInterval()
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
		return &HTTPStatusError{
			StatusCode: response.StatusCode,
			Status:     response.Status,
			Body:       string(responseBody),
		}
	}

	return nil
}

type HTTPStatusError struct {
	StatusCode int
	Status     string
	Body       string
}

func (e *HTTPStatusError) Error() string {
	return fmt.Sprintf("post notify returned %s: %s", e.Status, e.Body)
}

type retryClass int

const (
	retryStandard retryClass = iota
	retryShortUnavailable
	retryStop
)

func classifyRetry(err error) retryClass {
	var httpErr *HTTPStatusError
	if !errors.As(err, &httpErr) {
		return retryStandard
	}

	switch httpErr.StatusCode {
	case http.StatusServiceUnavailable:
		return retryShortUnavailable
	case http.StatusRequestTimeout, http.StatusTooManyRequests:
		return retryStandard
	}

	if httpErr.StatusCode >= 500 {
		return retryStandard
	}
	if httpErr.StatusCode >= 400 {
		return retryStop
	}
	return retryStandard
}
