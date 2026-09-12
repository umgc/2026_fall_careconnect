package toolkit

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
)

func backendBaseURL(repoRoot string) string {
	for _, key := range []string{"CARECONNECT_DEV_TOOLKIT_BASE_URL", "BACKEND_BASE_URL", "BASE_URL"} {
		if value := strings.TrimSpace(os.Getenv(key)); value != "" {
			return strings.TrimRight(value, "/")
		}
	}
	if parsed, err := readEnvFile(filepath.Join(repoRoot, "backend", "core", ".env"), "backend/core/.env"); err == nil && parsed.Found {
		for _, key := range []string{"CARECONNECT_DEV_TOOLKIT_BASE_URL", "BACKEND_BASE_URL", "BASE_URL"} {
			if value := strings.TrimSpace(parsed.Values[key]); value != "" {
				return strings.TrimRight(value, "/")
			}
		}
		if port := strings.TrimSpace(parsed.Values["SERVER_PORT"]); port != "" {
			return "http://localhost:" + port
		}
	}
	return "http://localhost:8080"
}

func CheckBackendHealth(ctx context.Context, baseURL string) (int, string, error) {
	baseURL = strings.TrimRight(baseURL, "/")
	if _, err := url.ParseRequestURI(baseURL); err != nil {
		return 0, "", fmt.Errorf("invalid base URL %q: %w", baseURL, err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, baseURL+"/v1/api/test/health", nil)
	if err != nil {
		return 0, "", err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0, "", err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
	return resp.StatusCode, strings.TrimSpace(string(body)), nil
}
