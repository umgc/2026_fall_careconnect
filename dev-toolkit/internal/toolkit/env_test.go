package toolkit

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// unsetEnvForTest guards a test against a stale value already exported in
// the shell running the test suite, restoring it afterward if it was set.
func unsetEnvForTest(t *testing.T, key string) {
	t.Helper()
	old, had := os.LookupEnv(key)
	os.Unsetenv(key)
	if had {
		t.Cleanup(func() { os.Setenv(key, old) })
	}
}

func TestPrintEnvPreview_FileValueTakesOneClearLine(t *testing.T) {
	const key = "CARECONNECT_TEST_PREVIEW_KEY"
	unsetEnvForTest(t, key)

	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.deploy"), []byte(key+"=file-value\n"), 0o600); err != nil {
		t.Fatalf("seed file: %v", err)
	}

	out := &bytes.Buffer{}
	app := NewApp(strings.NewReader(""), out, out)
	if err := app.printEnvPreview(dir, []string{".env.deploy"}, []string{key}); err != nil {
		t.Fatalf("printEnvPreview: %v", err)
	}

	text := out.String()
	// Exactly one resolved line for this key, naming its source file.
	if strings.Count(text, key) != 1 {
		t.Errorf("expected exactly one line mentioning %s, got:\n%s", key, text)
	}
	if !strings.Contains(text, "(.env.deploy)") {
		t.Errorf("expected the resolved line to name its source file, got:\n%s", text)
	}
	if strings.Contains(text, "current shell") {
		t.Errorf("a file-resolved value should not also print a separate current-shell section, got:\n%s", text)
	}
	if strings.Contains(text, "<unset>") {
		t.Errorf("a value present in the file must not be reported as unset, got:\n%s", text)
	}
}

func TestPrintEnvPreview_FallsBackToShellWhenFileMissingValue(t *testing.T) {
	const key = "CARECONNECT_TEST_PREVIEW_KEY_SHELL"
	unsetEnvForTest(t, key)
	os.Setenv(key, "shell-value")
	t.Cleanup(func() { os.Unsetenv(key) })

	dir := t.TempDir() // no .env.deploy at all

	out := &bytes.Buffer{}
	app := NewApp(strings.NewReader(""), out, out)
	if err := app.printEnvPreview(dir, []string{".env.deploy"}, []string{key}); err != nil {
		t.Fatalf("printEnvPreview: %v", err)
	}

	text := out.String()
	if !strings.Contains(text, "(current shell)") {
		t.Errorf("expected the value to resolve from the current shell, got:\n%s", text)
	}
	if strings.Contains(text, "<unset>") {
		t.Errorf("a shell-exported value must not be reported as unset, got:\n%s", text)
	}
}

func TestPrintEnvPreview_UnsetEverywhereShowsUnset(t *testing.T) {
	const key = "CARECONNECT_TEST_PREVIEW_KEY_MISSING"
	unsetEnvForTest(t, key)

	dir := t.TempDir()
	out := &bytes.Buffer{}
	app := NewApp(strings.NewReader(""), out, out)
	if err := app.printEnvPreview(dir, []string{".env.deploy"}, []string{key}); err != nil {
		t.Fatalf("printEnvPreview: %v", err)
	}

	text := out.String()
	if !strings.Contains(text, key+": <unset>") {
		t.Errorf("expected %s to be reported unset, got:\n%s", key, text)
	}
	if !strings.Contains(text, ".env.deploy: missing") {
		t.Errorf("expected the missing file itself to be noted, got:\n%s", text)
	}
}

func TestPrintEnvPreview_FileTakesPrecedenceOverShell(t *testing.T) {
	const key = "CARECONNECT_TEST_PREVIEW_KEY_PRECEDENCE"
	unsetEnvForTest(t, key)
	os.Setenv(key, "shell-value")
	t.Cleanup(func() { os.Unsetenv(key) })

	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, ".env.deploy"), []byte(key+"=file-value\n"), 0o600); err != nil {
		t.Fatalf("seed file: %v", err)
	}

	value, source, ok := resolveEnvValue([]envFileValues{
		{Path: ".env.deploy", Found: true, Values: map[string]string{key: "file-value"}},
	}, key)
	if !ok {
		t.Fatal("expected the key to resolve")
	}
	if value != "file-value" || source != ".env.deploy" {
		t.Errorf("expected the file value to take precedence over the shell, got value=%q source=%q", value, source)
	}
}
