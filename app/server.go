package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"sync/atomic"
	"time"
)

// config is read from the environment; see loadConfig for the variables and defaults.
type config struct {
	Port            int
	ShutdownDelay   time.Duration
	ShutdownTimeout time.Duration
	LogLevel        slog.Level
}

// loadConfig reads the configuration through getenv (os.Getenv in production).
//
//	PORT              TCP port to listen on (default 3000)
//	SHUTDOWN_DELAY    time to keep serving with /readyz failing after SIGTERM, so that
//	                  Service endpoints are updated before the listener closes (default 5s)
//	SHUTDOWN_TIMEOUT  maximum time to wait for in-flight requests to finish (default 20s)
//	LOG_LEVEL         debug, info, warn or error (default info)
func loadConfig(getenv func(string) string) (config, error) {
	cfg := config{
		Port:            3000,
		ShutdownDelay:   5 * time.Second,
		ShutdownTimeout: 20 * time.Second,
		LogLevel:        slog.LevelInfo,
	}
	if v := getenv("PORT"); v != "" {
		port, err := strconv.Atoi(v)
		if err != nil || port < 1 || port > 65535 {
			return cfg, fmt.Errorf("PORT must be a number between 1 and 65535, got %q", v)
		}
		cfg.Port = port
	}
	for name, dst := range map[string]*time.Duration{
		"SHUTDOWN_DELAY":   &cfg.ShutdownDelay,
		"SHUTDOWN_TIMEOUT": &cfg.ShutdownTimeout,
	} {
		v := getenv(name)
		if v == "" {
			continue
		}
		d, err := time.ParseDuration(v)
		if err != nil || d < 0 {
			return cfg, fmt.Errorf("%s must be a non-negative duration such as 5s, got %q", name, v)
		}
		*dst = d
	}
	if v := getenv("LOG_LEVEL"); v != "" {
		if err := cfg.LogLevel.UnmarshalText([]byte(v)); err != nil {
			return cfg, fmt.Errorf("LOG_LEVEL must be debug, info, warn or error, got %q", v)
		}
	}
	return cfg, nil
}

// app holds the state shared by the HTTP handlers.
type app struct {
	version  string
	hostname string
	logger   *slog.Logger
	ready    atomic.Bool
}

func (a *app) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /{$}", a.handleIndex)
	mux.HandleFunc("GET /healthz", a.handleHealthz)
	mux.HandleFunc("GET /readyz", a.handleReadyz)
	return a.logRequests(mux)
}

func (a *app) handleIndex(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"message":  "Hello from go-app",
		"version":  a.version,
		"hostname": a.hostname,
	})
}

// handleHealthz is the liveness probe: the process is up and serving HTTP.
func (a *app) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// handleReadyz is the readiness probe: it fails during startup and while shutting down.
func (a *app) handleReadyz(w http.ResponseWriter, _ *http.Request) {
	if !a.ready.Load() {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not ready"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

// logRequests writes one access log line per request, except for the probes.
func (a *app) logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			next.ServeHTTP(w, r)
			return
		}
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		a.logger.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration", time.Since(start),
			"remote", r.RemoteAddr,
		)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(status int) {
	r.status = status
	r.ResponseWriter.WriteHeader(status)
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

// serve runs the HTTP server on ln until ctx is cancelled, then shuts down gracefully:
// readiness fails first, the server keeps serving for cfg.ShutdownDelay so that load
// balancers stop sending traffic, and in-flight requests get cfg.ShutdownTimeout to finish.
func serve(ctx context.Context, ln net.Listener, a *app, cfg config) error {
	srv := &http.Server{
		Handler:           a.routes(),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
		ErrorLog:          slog.NewLogLogger(a.logger.Handler(), slog.LevelError),
	}

	errCh := make(chan error, 1)
	go func() { errCh <- srv.Serve(ln) }()
	a.ready.Store(true)
	a.logger.Info("listening", "addr", ln.Addr().String(), "version", a.version)

	select {
	case err := <-errCh:
		return fmt.Errorf("serve: %w", err)
	case <-ctx.Done():
	}

	a.ready.Store(false)
	a.logger.Info("shutting down", "delay", cfg.ShutdownDelay, "timeout", cfg.ShutdownTimeout)
	time.Sleep(cfg.ShutdownDelay)

	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}
	if err := <-errCh; !errors.Is(err, http.ErrServerClosed) {
		return fmt.Errorf("serve: %w", err)
	}
	a.logger.Info("stopped")
	return nil
}
