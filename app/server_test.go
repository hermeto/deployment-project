package main

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func newTestApp(ready bool) *app {
	a := &app{version: "1.2.3", hostname: "pod-0", logger: slog.New(slog.NewTextHandler(io.Discard, nil))}
	a.ready.Store(ready)
	return a
}

func TestLoadConfig(t *testing.T) {
	tests := []struct {
		name    string
		env     map[string]string
		want    config
		wantErr string
	}{
		{
			name: "defaults",
			want: config{Port: 3000, ShutdownDelay: 5 * time.Second, ShutdownTimeout: 20 * time.Second, LogLevel: slog.LevelInfo},
		},
		{
			name: "overrides",
			env:  map[string]string{"PORT": "8080", "SHUTDOWN_DELAY": "0s", "SHUTDOWN_TIMEOUT": "1m", "LOG_LEVEL": "debug"},
			want: config{Port: 8080, ShutdownDelay: 0, ShutdownTimeout: time.Minute, LogLevel: slog.LevelDebug},
		},
		{name: "port not a number", env: map[string]string{"PORT": "http"}, wantErr: "PORT"},
		{name: "port out of range", env: map[string]string{"PORT": "70000"}, wantErr: "PORT"},
		{name: "invalid delay", env: map[string]string{"SHUTDOWN_DELAY": "5"}, wantErr: "SHUTDOWN_DELAY"},
		{name: "negative timeout", env: map[string]string{"SHUTDOWN_TIMEOUT": "-1s"}, wantErr: "SHUTDOWN_TIMEOUT"},
		{name: "invalid log level", env: map[string]string{"LOG_LEVEL": "verbose"}, wantErr: "LOG_LEVEL"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := loadConfig(func(k string) string { return tt.env[k] })
			if tt.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
					t.Fatalf("loadConfig() error = %v, want an error mentioning %s", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("loadConfig() unexpected error: %v", err)
			}
			if got != tt.want {
				t.Fatalf("loadConfig() = %+v, want %+v", got, tt.want)
			}
		})
	}
}

func TestRoutes(t *testing.T) {
	tests := []struct {
		name       string
		ready      bool
		method     string
		path       string
		wantStatus int
		wantBody   map[string]string
	}{
		{"index", true, http.MethodGet, "/", http.StatusOK, map[string]string{"message": "Hello from go-app", "version": "1.2.3", "hostname": "pod-0"}},
		{"healthz", true, http.MethodGet, "/healthz", http.StatusOK, map[string]string{"status": "ok"}},
		{"healthz while not ready", false, http.MethodGet, "/healthz", http.StatusOK, map[string]string{"status": "ok"}},
		{"readyz", true, http.MethodGet, "/readyz", http.StatusOK, map[string]string{"status": "ready"}},
		{"readyz while not ready", false, http.MethodGet, "/readyz", http.StatusServiceUnavailable, map[string]string{"status": "not ready"}},
		{"head is allowed", true, http.MethodHead, "/healthz", http.StatusOK, nil},
		{"unknown path", true, http.MethodGet, "/nope", http.StatusNotFound, nil},
		{"wrong method", true, http.MethodPost, "/", http.StatusMethodNotAllowed, nil},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			newTestApp(tt.ready).routes().ServeHTTP(rec, httptest.NewRequest(tt.method, tt.path, nil))

			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d", rec.Code, tt.wantStatus)
			}
			if tt.wantBody == nil {
				return
			}
			if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
				t.Errorf("Content-Type = %q, want application/json", ct)
			}
			var got map[string]string
			if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
				t.Fatalf("invalid JSON body %q: %v", rec.Body.String(), err)
			}
			for k, v := range tt.wantBody {
				if got[k] != v {
					t.Errorf("body[%q] = %q, want %q", k, got[k], v)
				}
			}
		})
	}
}

// TestServeGracefulShutdown checks the shutdown sequence: once the context is cancelled,
// /readyz fails while the server keeps answering for the shutdown delay, then serve returns.
func TestServeGracefulShutdown(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	base := "http://" + ln.Addr().String()
	a := newTestApp(false)
	cfg := config{ShutdownDelay: 500 * time.Millisecond, ShutdownTimeout: 2 * time.Second}

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- serve(ctx, ln, a, cfg) }()

	waitForStatus(t, base+"/readyz", http.StatusOK)
	cancel()
	waitForStatus(t, base+"/readyz", http.StatusServiceUnavailable)
	if code := get(t, base+"/healthz"); code != http.StatusOK {
		t.Errorf("/healthz during the shutdown delay = %d, want 200", code)
	}

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("serve() returned %v, want nil", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("serve() did not return after shutdown")
	}
}

func get(t *testing.T, url string) int {
	t.Helper()
	client := &http.Client{Timeout: time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return 0
	}
	defer func() { _ = resp.Body.Close() }()
	return resp.StatusCode
}

func waitForStatus(t *testing.T, url string, want int) {
	t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for {
		got := get(t, url)
		if got == want {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("GET %s = %d, want %d", url, got, want)
		}
		time.Sleep(20 * time.Millisecond)
	}
}
