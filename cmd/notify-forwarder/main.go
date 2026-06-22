package main

import (
	"context"
	"errors"
	"flag"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/fsnotify/fsnotify"
)

type sendResult struct {
	eventKey string
	state    State
	err      error
}

func main() {
	configPath := flag.String("config", "cmd/notify-forwarder/config.json", "path to notify forwarder config JSON")
	flag.Parse()

	config, err := LoadConfig(*configPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	inputPath, err := filepath.Abs(config.InputPath)
	if err != nil {
		log.Fatalf("resolve input_path: %v", err)
	}
	config.InputPath = inputPath

	state, err := LoadState(config.StatePath)
	if err != nil {
		log.Fatalf("load state: %v", err)
	}

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Fatalf("create watcher: %v", err)
	}
	defer watcher.Close()

	inputDir := filepath.Dir(config.InputPath)
	inputBase := filepath.Base(config.InputPath)
	if err := watcher.Add(inputDir); err != nil {
		log.Fatalf("watch %s: %v", inputDir, err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	triggers := make(chan string, 1)
	results := make(chan sendResult, 1)
	trigger := func(reason string) {
		select {
		case triggers <- reason:
		default:
		}
	}

	log.Printf("notify forwarder started")
	log.Printf("input_path=%s", config.InputPath)
	log.Printf("notify_url=%s", config.NotifyURL)
	log.Printf("state_path=%s", config.StatePath)
	log.Printf("watching directory=%s file=%s", inputDir, inputBase)

	go watchInput(ctx, watcher, config.InputPath, trigger)
	trigger("startup")

	var timer *time.Timer
	var timerC <-chan time.Time
	var activeCancel context.CancelFunc
	var activeEventKey string

	for {
		select {
		case <-ctx.Done():
			if activeCancel != nil {
				activeCancel()
			}
			log.Printf("notify forwarder stopped")
			return

		case reason := <-triggers:
			log.Printf("input change detected: %s", reason)
			if timer != nil {
				timer.Stop()
			}
			timer = time.NewTimer(config.Debounce())
			timerC = timer.C

		case <-timerC:
			timer = nil
			timerC = nil

			snapshot, err := ReadInputSnapshot(config)
			if err != nil {
				if errors.Is(err, os.ErrNotExist) {
					log.Printf("input file does not exist yet: %s", config.InputPath)
					continue
				}
				log.Printf("read input: %v", err)
				continue
			}

			if snapshot.EventKey == state.LastEventKey {
				log.Printf("skip already notified event: updated_at=%s", snapshot.UpdatedAt)
				continue
			}
			if snapshot.EventKey == activeEventKey {
				log.Printf("skip event already being sent: updated_at=%s", snapshot.UpdatedAt)
				continue
			}

			if activeCancel != nil {
				log.Printf("cancel older pending notification")
				activeCancel()
			}

			sendCtx, cancel := context.WithCancel(ctx)
			activeCancel = cancel
			activeEventKey = snapshot.EventKey
			go func(snapshot InputSnapshot) {
				resultState, err := SendWithRetry(sendCtx, config, snapshot)
				results <- sendResult{
					eventKey: snapshot.EventKey,
					state:    resultState,
					err:      err,
				}
			}(snapshot)

		case result := <-results:
			if result.eventKey != activeEventKey {
				continue
			}

			activeEventKey = ""
			activeCancel = nil

			if result.err != nil {
				if errors.Is(result.err, context.Canceled) {
					log.Printf("notification send canceled because a newer update arrived")
					continue
				}
				log.Printf("notification send failed: %v", result.err)
				continue
			}

			state = result.state
			if err := SaveState(config.StatePath, state); err != nil {
				log.Printf("save state: %v", err)
			}
		}
	}
}

func watchInput(ctx context.Context, watcher *fsnotify.Watcher, inputPath string, trigger func(string)) {
	cleanInput := filepath.Clean(inputPath)

	for {
		select {
		case <-ctx.Done():
			return

		case event, ok := <-watcher.Events:
			if !ok {
				return
			}

			if filepath.Clean(event.Name) != cleanInput {
				continue
			}
			if event.Op&(fsnotify.Create|fsnotify.Write|fsnotify.Rename|fsnotify.Chmod) == 0 {
				continue
			}

			trigger(event.Op.String())

		case err, ok := <-watcher.Errors:
			if !ok {
				return
			}
			log.Printf("watch error: %v", err)
		}
	}
}
