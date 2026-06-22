package main

import (
	"encoding/json"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"time"
)

type Config struct {
	InputPath                         string `json:"input_path"`
	NotifyURL                         string `json:"notify_url"`
	StatePath                         string `json:"state_path"`
	DefaultLevel                      string `json:"default_level"`
	DefaultDurationMS                 int    `json:"default_duration_ms"`
	DebounceMS                        int    `json:"debounce_ms"`
	RequestTimeoutMS                  int    `json:"request_timeout_ms"`
	RetryInitialIntervalMS            int    `json:"retry_initial_interval_ms"`
	RetryMaxIntervalMS                int    `json:"retry_max_interval_ms"`
	RetryUnavailableInitialIntervalMS int    `json:"retry_unavailable_initial_interval_ms"`
	RetryUnavailableMaxIntervalMS     int    `json:"retry_unavailable_max_interval_ms"`
	RetryMaxElapsedMS                 int    `json:"retry_max_elapsed_ms"`
}

func LoadConfig(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, err
	}

	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return Config{}, err
	}

	config = config.withDefaults()
	if err := config.validate(); err != nil {
		return Config{}, err
	}

	return config, nil
}

func (c Config) withDefaults() Config {
	if c.DefaultLevel == "" {
		c.DefaultLevel = "info"
	}
	if c.DefaultDurationMS <= 0 {
		c.DefaultDurationMS = 5000
	}
	if c.DebounceMS <= 0 {
		c.DebounceMS = 120
	}
	if c.RequestTimeoutMS <= 0 {
		c.RequestTimeoutMS = 5000
	}
	if c.RetryInitialIntervalMS <= 0 {
		c.RetryInitialIntervalMS = 1000
	}
	if c.RetryMaxIntervalMS <= 0 {
		c.RetryMaxIntervalMS = 300000
	}
	if c.RetryUnavailableInitialIntervalMS <= 0 {
		c.RetryUnavailableInitialIntervalMS = 5000
	}
	if c.RetryUnavailableMaxIntervalMS <= 0 {
		c.RetryUnavailableMaxIntervalMS = 30000
	}
	if c.RetryMaxElapsedMS <= 0 {
		c.RetryMaxElapsedMS = 1800000
	}
	if c.StatePath == "" && c.InputPath != "" {
		c.StatePath = c.InputPath + ".notify-forwarder-state.json"
	}
	return c
}

func (c Config) validate() error {
	if c.InputPath == "" {
		return fmt.Errorf("input_path is required")
	}
	if c.NotifyURL == "" {
		return fmt.Errorf("notify_url is required")
	}
	parsedURL, err := url.Parse(c.NotifyURL)
	if err != nil || parsedURL.Scheme == "" || parsedURL.Host == "" {
		return fmt.Errorf("notify_url must be an absolute URL")
	}
	if c.StatePath == "" {
		return fmt.Errorf("state_path is required")
	}
	return nil
}

func (c Config) Debounce() time.Duration {
	return time.Duration(c.DebounceMS) * time.Millisecond
}

func (c Config) RequestTimeout() time.Duration {
	return time.Duration(c.RequestTimeoutMS) * time.Millisecond
}

func (c Config) RetryInitialInterval() time.Duration {
	return time.Duration(c.RetryInitialIntervalMS) * time.Millisecond
}

func (c Config) RetryMaxInterval() time.Duration {
	return time.Duration(c.RetryMaxIntervalMS) * time.Millisecond
}

func (c Config) RetryUnavailableInitialInterval() time.Duration {
	return time.Duration(c.RetryUnavailableInitialIntervalMS) * time.Millisecond
}

func (c Config) RetryUnavailableMaxInterval() time.Duration {
	return time.Duration(c.RetryUnavailableMaxIntervalMS) * time.Millisecond
}

func (c Config) RetryMaxElapsed() time.Duration {
	return time.Duration(c.RetryMaxElapsedMS) * time.Millisecond
}

func ensureParentDir(path string) error {
	return os.MkdirAll(filepath.Dir(path), 0o755)
}
