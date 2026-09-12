// Package tests holds black-box integration tests for dev-toolkit. Unlike
// internal/toolkit/*_test.go (which must live inside the package to reach
// unexported internals — a Go language requirement, not a style choice),
// everything here only uses toolkit's exported surface: NewApp/App.Run,
// LoadCatalog, Catalog.*, FindRepoRoot, CheckBackendHealth. These tests
// drive the CLI exactly the way a real invocation would (piped stdin,
// captured stdout), so they exercise real end-to-end behavior rather than
// individual functions in isolation.
package tests

import (
	"bytes"
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"careconnect/dev-toolkit/internal/toolkit"
)

// runApp is a small helper: builds a fresh App wired to the given stdin,
// runs it with args, and returns combined stdout+stderr plus any error.
func runApp(t *testing.T, stdin string, args ...string) (string, error) {
	t.Helper()
	var out bytes.Buffer
	app := toolkit.NewApp(strings.NewReader(stdin), &out, &out)
	err := app.Run(args)
	return out.String(), err
}

// scaffoldRepo makes an empty temp directory usable as --repo for tests that
// never actually execute a shell command (always decline the final "Run
// this command?" prompt), so no real script needs to exist on disk.
func scaffoldRepo(t *testing.T) string {
	t.Helper()
	return t.TempDir()
}

func TestList_ShowsEveryCommandWithPlatformLabel(t *testing.T) {
	repo := scaffoldRepo(t)
	out, err := runApp(t, "", "--repo", repo, "--list")
	if err != nil {
		t.Fatalf("--list: %v", err)
	}
	for _, id := range []string{
		"backend.start", "infra.deploy.full", "infra.deploy.app", "infra.destroy",
		"scripts.browser", "toolkit.status",
	} {
		if !strings.Contains(out, id) {
			t.Errorf("expected --list output to contain %q, got:\n%s", id, out)
		}
	}
	if !strings.Contains(out, "[native]") || !strings.Contains(out, "[posix ]") {
		t.Errorf("expected both platform labels to appear, got:\n%s", out)
	}
}

func TestDryRun_NativeCommand_PreviewsWithoutExecuting(t *testing.T) {
	repo := scaffoldRepo(t)
	out, err := runApp(t, "", "--repo", repo, "--dry-run", "backend.start")
	if err != nil {
		t.Fatalf("--dry-run backend.start: %v", err)
	}
	if !strings.Contains(out, "Start backend in dev mode") {
		t.Errorf("expected the command title in preview output, got:\n%s", out)
	}
	if !strings.Contains(out, "Command:") {
		t.Errorf("expected a Command: line in preview output, got:\n%s", out)
	}
	if strings.Contains(out, "Run this command?") {
		t.Errorf("dry-run must never reach the run confirmation, got:\n%s", out)
	}
}

func TestDryRun_UnknownID_Errors(t *testing.T) {
	repo := scaffoldRepo(t)
	_, err := runApp(t, "", "--repo", repo, "--dry-run", "does.not.exist")
	if err == nil {
		t.Fatal("expected an error for an unknown command id")
	}
}

func TestDryRun_InfraDeployFull_WarnsMissingSecretsWithoutWriting(t *testing.T) {
	repo := scaffoldRepo(t)
	if err := os.MkdirAll(filepath.Join(repo, "cloudformation-fargate"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	// 7 catalog inputs for infra.deploy.full: environment, profile, region,
	// image_tag, run_tests, ai_enabled, ai_model. Dry-run stops before any
	// secrets/run confirm.
	out, err := runApp(t, "1\n\n\n\n\n\n\n", "--repo", repo, "--dry-run", "infra.deploy.full")
	if err != nil {
		t.Fatalf("--dry-run infra.deploy.full: %v", err)
	}
	if !strings.Contains(out, "Warning:") || !strings.Contains(out, "is missing") {
		t.Errorf("expected a missing-secrets warning, got:\n%s", out)
	}
	if !strings.Contains(out, "dry-run") {
		t.Errorf("expected the warning to identify itself as dry-run-only, got:\n%s", out)
	}
	if _, statErr := os.Stat(filepath.Join(repo, "cloudformation-fargate", ".env.deploy")); !os.IsNotExist(statErr) {
		t.Errorf(".env.deploy must not be written during --dry-run, stat err = %v", statErr)
	}
}

func TestDryRun_WithSetFlags_SkipsAllPromptsAndResolvesCommand(t *testing.T) {
	repo := scaffoldRepo(t)
	if err := os.MkdirAll(filepath.Join(repo, "cloudformation-fargate"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	// Every input for infra.deploy.full is preset, so empty stdin must be
	// enough to reach a resolved command line with no prompts blocking on
	// input at all.
	out, err := runApp(t, "",
		"--repo", repo, "--dry-run", "infra.deploy.full",
		"-set", "environment=dev",
		"-set", "profile=myprofile",
		"-set", "region=us-west-2",
		"-set", "image_tag=custom-tag",
		"-set", "run_tests=false",
		"-set", "ai_enabled=true",
		"-set", "ai_model=amazon.nova-lite-v1:0",
	)
	if err != nil {
		t.Fatalf("--dry-run infra.deploy.full with -set: %v", err)
	}
	wantCmd := "Command: bash cloudformation-fargate/cdeploy_cloudformation.sh " +
		"--environment dev --profile myprofile --region us-west-2 --image-tag custom-tag " +
		"--ai-enabled true --ai-model amazon.nova-lite-v1:0"
	if !strings.Contains(out, wantCmd) {
		t.Errorf("expected resolved command %q, got:\n%s", wantCmd, out)
	}
	if strings.Count(out, "(preset)") != 7 {
		t.Errorf("expected all 7 inputs to report as preset, got:\n%s", out)
	}
}

func TestDryRun_WithSetFlags_ChoiceAcceptsIndexOrLiteral(t *testing.T) {
	repo := scaffoldRepo(t)
	if err := os.MkdirAll(filepath.Join(repo, "cloudformation-fargate"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	// "1" is the 1-based index into the environment choice list (dev is
	// first) — presets must accept the same forms promptChoice does
	// interactively.
	out, err := runApp(t, "\n\n\n\n\n\n",
		"--repo", repo, "--dry-run", "infra.deploy.full",
		"-set", "environment=1",
	)
	if err != nil {
		t.Fatalf("--dry-run infra.deploy.full with -set environment=1: %v", err)
	}
	if !strings.Contains(out, "Environment: dev (preset)") {
		t.Errorf("expected numeric preset to resolve to 'dev', got:\n%s", out)
	}
}

func TestDryRun_WithSetFlags_UnknownKeyWarnsButDoesNotFail(t *testing.T) {
	repo := scaffoldRepo(t)
	if err := os.MkdirAll(filepath.Join(repo, "cloudformation-fargate"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	out, err := runApp(t, "1\n\n\n\n\n\n\n",
		"--repo", repo, "--dry-run", "infra.deploy.full",
		"-set", "not_a_real_input=oops",
	)
	if err != nil {
		t.Fatalf("--dry-run infra.deploy.full with unknown -set: %v", err)
	}
	if !strings.Contains(out, "warning: -set not_a_real_input does not match any input for this command") {
		t.Errorf("expected an unknown-key warning, got:\n%s", out)
	}
}

func TestDryRun_WithSetFlags_InvalidBoolErrors(t *testing.T) {
	repo := scaffoldRepo(t)
	if err := os.MkdirAll(filepath.Join(repo, "cloudformation-fargate"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	_, err := runApp(t, "1\n\n\n\n\n",
		"--repo", repo, "--dry-run", "infra.deploy.full",
		"-set", "run_tests=maybe",
	)
	if err == nil {
		t.Fatal("expected an error for an invalid bool preset, got nil")
	}
	if !strings.Contains(err.Error(), "run_tests") {
		t.Errorf("expected the error to name the offending input, got: %v", err)
	}
}

func TestRun_InfraDeployFull_DeclineEverything_NoSideEffects(t *testing.T) {
	repo := scaffoldRepo(t)
	if err := os.MkdirAll(filepath.Join(repo, "cloudformation-fargate"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	// 7 catalog inputs, then "n" to decline secret generation, then "n" to
	// decline the final run — the underlying (nonexistent) deploy script
	// must never actually be invoked.
	out, err := runApp(t, "1\n\n\n\n\n\n\nn\nn\n", "--repo", repo, "--run", "infra.deploy.full")
	if err != nil {
		t.Fatalf("--run infra.deploy.full (decline all): %v", err)
	}
	if !strings.Contains(out, "Skipped") {
		t.Errorf("expected the run to be skipped, got:\n%s", out)
	}
	if _, statErr := os.Stat(filepath.Join(repo, "cloudformation-fargate", ".env.deploy")); !os.IsNotExist(statErr) {
		t.Errorf(".env.deploy must not be written after declining generation, stat err = %v", statErr)
	}
}

func TestRun_InfraDeployFull_ConfirmSecretsDeclineRun_WritesSecretsOnly(t *testing.T) {
	repo := scaffoldRepo(t)
	if err := os.MkdirAll(filepath.Join(repo, "cloudformation-fargate"), 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	// Same 7 catalog inputs, "y" to generate secrets, "n" to decline the
	// actual (nonexistent-script) run. If this incorrectly proceeded to
	// execute, runProcess would fail trying to exec a script that doesn't
	// exist in this scaffolded repo, and this test's err check would catch it.
	out, err := runApp(t, "1\n\n\n\n\n\n\ny\nn\n", "--repo", repo, "--run", "infra.deploy.full")
	if err != nil {
		t.Fatalf("--run infra.deploy.full (confirm secrets, decline run): %v", err)
	}
	if !strings.Contains(out, "Wrote generated values") {
		t.Errorf("expected confirmation that secrets were written, got:\n%s", out)
	}

	envPath := filepath.Join(repo, "cloudformation-fargate", ".env.deploy")
	data, err := os.ReadFile(envPath)
	if err != nil {
		t.Fatalf("expected .env.deploy to exist: %v", err)
	}
	content := string(data)
	if !strings.Contains(content, "CARECONNECT_DATABASE_MASTER_PASSWORD=") ||
		!strings.Contains(content, "CARECONNECT_JWT_SECRET=") {
		t.Errorf("expected both secret keys in .env.deploy, got:\n%s", content)
	}
	if strings.Contains(content, "REPLACE_ME") {
		t.Errorf("generated file should not contain leftover placeholder text, got:\n%s", content)
	}
}

func TestRun_InfraDeployFull_AlreadySetSecrets_SkipsPromptEntirely(t *testing.T) {
	repo := scaffoldRepo(t)
	cfDir := filepath.Join(repo, "cloudformation-fargate")
	if err := os.MkdirAll(cfDir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}
	seed := "CARECONNECT_DATABASE_MASTER_PASSWORD=already-set\nCARECONNECT_JWT_SECRET=already-set\n"
	if err := os.WriteFile(filepath.Join(cfDir, ".env.deploy"), []byte(seed), 0o600); err != nil {
		t.Fatalf("seed .env.deploy: %v", err)
	}

	// Only 8 tokens this time (7 catalog inputs + final decline) — no 9th
	// token for a secrets-generation confirm. If the code incorrectly
	// prompted for secrets anyway, the final "Run this command?" read would
	// hit EOF and this call would return an error, failing the test.
	out, err := runApp(t, "1\n\n\n\n\n\n\nn\n", "--repo", repo, "--run", "infra.deploy.full")
	if err != nil {
		t.Fatalf("--run infra.deploy.full (secrets already set): %v", err)
	}
	if strings.Contains(out, "is missing") {
		t.Errorf("should not report anything missing when both secrets are already set, got:\n%s", out)
	}

	data, err := os.ReadFile(filepath.Join(cfDir, ".env.deploy"))
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	if string(data) != seed {
		t.Errorf("existing .env.deploy should be untouched, got:\n%s", string(data))
	}
}

func TestCatalog_LookupAndSearch(t *testing.T) {
	catalog, err := toolkit.LoadCatalog("")
	if err != nil {
		t.Fatalf("LoadCatalog: %v", err)
	}
	if err := catalog.Validate(); err != nil {
		t.Fatalf("Validate: %v", err)
	}

	if _, ok := catalog.Find("infra.deploy.full"); !ok {
		t.Error("expected to find infra.deploy.full")
	}
	if _, ok := catalog.Find("does.not.exist"); ok {
		t.Error("did not expect to find a nonexistent command id")
	}

	categories := catalog.Categories()
	if len(categories) == 0 {
		t.Error("expected at least one category")
	}
	found := false
	for _, c := range categories {
		if c == "CloudFormation" {
			found = true
			inCategory := catalog.CommandsInCategory(c)
			if len(inCategory) < 3 {
				t.Errorf("expected at least 3 CloudFormation commands, got %d", len(inCategory))
			}
		}
	}
	if !found {
		t.Errorf("expected a CloudFormation category, got: %v", categories)
	}

	results := catalog.Search("deploy")
	if len(results) == 0 {
		t.Error("expected Search(\"deploy\") to find at least one command")
	}
}

func TestFindRepoRoot(t *testing.T) {
	dir := t.TempDir()
	for _, sub := range []string{"backend/core", "quality", "cloudformation-fargate"} {
		if err := os.MkdirAll(filepath.Join(dir, sub), 0o755); err != nil {
			t.Fatalf("mkdir %s: %v", sub, err)
		}
	}
	nested := filepath.Join(dir, "backend", "core", "src")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatalf("mkdir nested: %v", err)
	}

	root, err := toolkit.FindRepoRoot(nested)
	if err != nil {
		t.Fatalf("FindRepoRoot from nested dir: %v", err)
	}
	resolvedDir, _ := filepath.EvalSymlinks(dir)
	resolvedRoot, _ := filepath.EvalSymlinks(root)
	if resolvedRoot != resolvedDir {
		t.Errorf("expected repo root %s, got %s", resolvedDir, resolvedRoot)
	}

	emptyDir := t.TempDir()
	if _, err := toolkit.FindRepoRoot(emptyDir); err == nil {
		t.Error("expected an error when no repo markers are present")
	}
}

func TestCheckBackendHealth(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/api/test/health" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	}))
	defer server.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	status, body, err := toolkit.CheckBackendHealth(ctx, server.URL)
	if err != nil {
		t.Fatalf("CheckBackendHealth: %v", err)
	}
	if status != http.StatusOK {
		t.Errorf("expected 200, got %d", status)
	}
	if body != "ok" {
		t.Errorf("expected body %q, got %q", "ok", body)
	}
}

func TestCheckBackendHealth_ServerError(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte("boom"))
	}))
	defer server.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	status, _, err := toolkit.CheckBackendHealth(ctx, server.URL)
	if err != nil {
		t.Fatalf("CheckBackendHealth should not error on a 500, just report it: %v", err)
	}
	if status != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", status)
	}
}

func TestCheckBackendHealth_InvalidURL(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if _, _, err := toolkit.CheckBackendHealth(ctx, "not a url"); err == nil {
		t.Error("expected an error for an invalid base URL")
	}
}
