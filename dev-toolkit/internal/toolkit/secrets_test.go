package toolkit

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// unsetDeploySecretEnv guards against a stale CARECONNECT_DATABASE_MASTER_PASSWORD
// / CARECONNECT_JWT_SECRET already exported in the test-running shell, which
// would make ensureGeneratedSecrets treat them as "already set" regardless of
// the file under test.
func unsetDeploySecretEnv(t *testing.T) {
	t.Helper()
	for _, key := range []string{"CARECONNECT_DATABASE_MASTER_PASSWORD", "CARECONNECT_JWT_SECRET"} {
		old, had := os.LookupEnv(key)
		os.Unsetenv(key)
		if had {
			t.Cleanup(func() { os.Setenv(key, old) })
		}
	}
}

func testCommand(dir string) Command {
	return Command{
		GenerateSecretsFile: filepath.Join(dir, ".env.deploy"),
		GenerateSecrets: []SecretSpec{
			{Key: "CARECONNECT_DATABASE_MASTER_PASSWORD", Bytes: 16},
			{Key: "CARECONNECT_JWT_SECRET", Bytes: 32},
		},
	}
}

func TestEnsureGeneratedSecrets_DeclineWritesNothing(t *testing.T) {
	unsetDeploySecretEnv(t)
	dir := t.TempDir()
	cmd := testCommand(".")
	cmd.GenerateSecretsFile = ".env.deploy"

	out := &bytes.Buffer{}
	app := NewApp(strings.NewReader("n\n"), out, out)

	if err := app.ensureGeneratedSecrets(dir, cmd); err != nil {
		t.Fatalf("ensureGeneratedSecrets: %v", err)
	}

	if _, err := os.Stat(filepath.Join(dir, ".env.deploy")); !os.IsNotExist(err) {
		t.Fatalf(".env.deploy should not exist after declining, stat err = %v", err)
	}
	if !strings.Contains(out.String(), "is missing") {
		t.Errorf("expected a 'is missing' notice, got:\n%s", out.String())
	}
	if !strings.Contains(out.String(), "Skipped") {
		t.Errorf("expected a 'Skipped' notice on decline, got:\n%s", out.String())
	}
}

func TestEnsureGeneratedSecrets_ConfirmWritesValidSecrets(t *testing.T) {
	unsetDeploySecretEnv(t)
	dir := t.TempDir()
	cmd := testCommand(".")
	cmd.GenerateSecretsFile = ".env.deploy"

	out := &bytes.Buffer{}
	app := NewApp(strings.NewReader("y\n"), out, out)

	if err := app.ensureGeneratedSecrets(dir, cmd); err != nil {
		t.Fatalf("ensureGeneratedSecrets: %v", err)
	}

	data, err := os.ReadFile(filepath.Join(dir, ".env.deploy"))
	if err != nil {
		t.Fatalf("expected .env.deploy to be written: %v", err)
	}

	written, err := readEnvFile(filepath.Join(dir, ".env.deploy"), ".env.deploy")
	if err != nil {
		t.Fatalf("readEnvFile: %v", err)
	}
	pw := written.Values["CARECONNECT_DATABASE_MASTER_PASSWORD"]
	jwt := written.Values["CARECONNECT_JWT_SECRET"]
	if len(pw) != 32 { // 16 bytes hex-encoded
		t.Errorf("password: expected 32 hex chars (16 bytes), got %d: %q", len(pw), pw)
	}
	if len(jwt) != 64 { // 32 bytes hex-encoded
		t.Errorf("jwt secret: expected 64 hex chars (32 bytes), got %d: %q", len(jwt), jwt)
	}
	if pw == jwt {
		t.Errorf("password and jwt secret should not be identical: got the same value twice")
	}

	// Written secret values themselves must never be echoed to the terminal.
	if strings.Contains(out.String(), pw) || strings.Contains(out.String(), jwt) {
		t.Errorf("generated secret values must not be printed to output, got:\n%s", out.String())
	}

	info, err := os.Stat(filepath.Join(dir, ".env.deploy"))
	if err != nil {
		t.Fatalf("stat: %v", err)
	}
	if perm := info.Mode().Perm(); perm != 0o600 {
		t.Errorf("expected 0600 permissions on a freshly created secrets file, got %o", perm)
	}

	_ = data // presence already confirmed via ReadFile above
}

func TestEnsureGeneratedSecrets_AlreadySetSkipsPromptEntirely(t *testing.T) {
	dir := t.TempDir()
	envPath := filepath.Join(dir, ".env.deploy")
	content := "CARECONNECT_DATABASE_MASTER_PASSWORD=already-set-password\n" +
		"CARECONNECT_JWT_SECRET=already-set-jwt-secret-value\n"
	if err := os.WriteFile(envPath, []byte(content), 0o600); err != nil {
		t.Fatalf("seed file: %v", err)
	}

	cmd := testCommand(".")
	cmd.GenerateSecretsFile = ".env.deploy"

	out := &bytes.Buffer{}
	// No input available — if the code tried to prompt, ReadString would
	// hit EOF and the function would return an error, failing this test.
	app := NewApp(strings.NewReader(""), out, out)

	if err := app.ensureGeneratedSecrets(dir, cmd); err != nil {
		t.Fatalf("ensureGeneratedSecrets should no-op without reading stdin: %v", err)
	}

	data, err := os.ReadFile(envPath)
	if err != nil {
		t.Fatalf("read back: %v", err)
	}
	if string(data) != content {
		t.Errorf("file should be untouched when both secrets are already set, got:\n%s", string(data))
	}
	if out.String() != "" {
		t.Errorf("expected no output when nothing is missing, got:\n%s", out.String())
	}
}

func TestWarnMissingSecrets_NoPromptNoWrite(t *testing.T) {
	unsetDeploySecretEnv(t)
	dir := t.TempDir()
	cmd := testCommand(".")
	cmd.GenerateSecretsFile = ".env.deploy"

	out := &bytes.Buffer{}
	// No stdin available — warnMissingSecrets must never try to read it.
	app := NewApp(strings.NewReader(""), out, out)

	if err := app.warnMissingSecrets(dir, cmd); err != nil {
		t.Fatalf("warnMissingSecrets: %v", err)
	}

	if _, err := os.Stat(filepath.Join(dir, ".env.deploy")); !os.IsNotExist(err) {
		t.Fatalf(".env.deploy should not exist after a dry-run warning, stat err = %v", err)
	}
	if !strings.Contains(out.String(), "Warning:") || !strings.Contains(out.String(), "is missing") {
		t.Errorf("expected a warning notice, got:\n%s", out.String())
	}
	if !strings.Contains(out.String(), "dry-run") {
		t.Errorf("expected the message to identify itself as a dry-run notice, got:\n%s", out.String())
	}
}

func TestWarnMissingSecrets_SilentWhenAlreadySet(t *testing.T) {
	dir := t.TempDir()
	envPath := filepath.Join(dir, ".env.deploy")
	content := "CARECONNECT_DATABASE_MASTER_PASSWORD=already-set\nCARECONNECT_JWT_SECRET=already-set\n"
	if err := os.WriteFile(envPath, []byte(content), 0o600); err != nil {
		t.Fatalf("seed file: %v", err)
	}
	cmd := testCommand(".")
	cmd.GenerateSecretsFile = ".env.deploy"

	out := &bytes.Buffer{}
	app := NewApp(strings.NewReader(""), out, out)

	if err := app.warnMissingSecrets(dir, cmd); err != nil {
		t.Fatalf("warnMissingSecrets: %v", err)
	}
	if out.String() != "" {
		t.Errorf("expected no output when nothing is missing, got:\n%s", out.String())
	}
}

func TestEnsureGeneratedSecrets_SeedsFromEnvExample(t *testing.T) {
	unsetDeploySecretEnv(t)
	dir := t.TempDir()
	example := "# header comment\nCARECONNECT_DATABASE_MASTER_PASSWORD=\nCARECONNECT_JWT_SECRET=\n"
	if err := os.WriteFile(filepath.Join(dir, ".env.example"), []byte(example), 0o644); err != nil {
		t.Fatalf("seed example: %v", err)
	}

	cmd := testCommand(".")
	cmd.GenerateSecretsFile = ".env.deploy"

	out := &bytes.Buffer{}
	app := NewApp(strings.NewReader("y\n"), out, out)

	if err := app.ensureGeneratedSecrets(dir, cmd); err != nil {
		t.Fatalf("ensureGeneratedSecrets: %v", err)
	}

	data, err := os.ReadFile(filepath.Join(dir, ".env.deploy"))
	if err != nil {
		t.Fatalf("expected .env.deploy to be written: %v", err)
	}
	if !strings.Contains(string(data), "# header comment") {
		t.Errorf("expected .env.example's header comment to survive, got:\n%s", string(data))
	}
}
