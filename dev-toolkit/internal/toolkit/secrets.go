package toolkit

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// findMissingSecrets returns the keys in cmd.GenerateSecrets that are unset
// (or empty) both in the current shell and in cmd.GenerateSecretsFile. Purely
// read-only — safe to call during --dry-run. Returns nil if the command
// declares no GenerateSecrets.
func findMissingSecrets(repoRoot string, cmd Command) ([]string, error) {
	if len(cmd.GenerateSecrets) == 0 || cmd.GenerateSecretsFile == "" {
		return nil, nil
	}
	absPath := filepath.Join(repoRoot, filepath.FromSlash(cmd.GenerateSecretsFile))
	existing, err := readEnvFile(absPath, cmd.GenerateSecretsFile)
	if err != nil {
		return nil, err
	}
	var missing []string
	for _, spec := range cmd.GenerateSecrets {
		if value, ok := existing.Values[spec.Key]; ok && value != "" {
			continue
		}
		if value, ok := os.LookupEnv(spec.Key); ok && value != "" {
			continue
		}
		missing = append(missing, spec.Key)
	}
	return missing, nil
}

// warnMissingSecrets prints a notice (no prompt, no file write) when
// cmd.GenerateSecrets has entries unset both in the shell and in
// cmd.GenerateSecretsFile. Used during --dry-run, which must stay
// side-effect-free — this is the read-only counterpart to
// ensureGeneratedSecrets below.
func (a *App) warnMissingSecrets(repoRoot string, cmd Command) error {
	missing, err := findMissingSecrets(repoRoot, cmd)
	if err != nil {
		return err
	}
	if len(missing) == 0 {
		return nil
	}
	fmt.Fprintln(a.out)
	fmt.Fprintf(a.out, "Warning: %s is missing: %s\n", cmd.GenerateSecretsFile, strings.Join(missing, ", "))
	fmt.Fprintln(a.out, "(dry-run: not generating — rerun with --run to be offered generated values)")
	return nil
}

// ensureGeneratedSecrets offers to generate and save random values for any of
// cmd.GenerateSecrets that are unset both in the current shell and in
// cmd.GenerateSecretsFile. Requires explicit user confirmation before writing
// anything — never generates silently. No-op if the command declares no
// GenerateSecrets, or if every key already has a value somewhere. Only call
// this for a real run — it prompts and writes files, so it must never run
// during --dry-run (use warnMissingSecrets there instead).
func (a *App) ensureGeneratedSecrets(repoRoot string, cmd Command) error {
	missing, err := findMissingSecrets(repoRoot, cmd)
	if err != nil {
		return err
	}
	if len(missing) == 0 {
		return nil
	}

	fmt.Fprintln(a.out)
	fmt.Fprintf(a.out, "%s is missing: %s\n", cmd.GenerateSecretsFile, strings.Join(missing, ", "))
	ok, err := a.confirm(
		fmt.Sprintf("Generate secure random values for these and save them to %s?", cmd.GenerateSecretsFile),
		false)
	if err != nil {
		return err
	}
	if !ok {
		fmt.Fprintln(a.out, "Skipped — deploy may fail until these are set.")
		return nil
	}

	updates := make(map[string]string, len(missing))
	for _, spec := range cmd.GenerateSecrets {
		if !containsKey(missing, spec.Key) {
			continue
		}
		value, genErr := randomHex(spec.Bytes)
		if genErr != nil {
			return genErr
		}
		updates[spec.Key] = value
	}

	absPath := filepath.Join(repoRoot, filepath.FromSlash(cmd.GenerateSecretsFile))
	if err := upsertEnvValues(absPath, updates); err != nil {
		return err
	}
	fmt.Fprintf(a.out, "Wrote generated values to %s (values are not printed here — see the file if you need them).\n", cmd.GenerateSecretsFile)
	return nil
}

func containsKey(keys []string, key string) bool {
	for _, k := range keys {
		if k == key {
			return true
		}
	}
	return false
}

// randomHex returns n cryptographically random bytes, hex-encoded. Falls
// back to 32 bytes for a non-positive n rather than producing an empty or
// surprising-length secret.
func randomHex(n int) (string, error) {
	if n <= 0 {
		n = 32
	}
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return "", fmt.Errorf("generate random bytes: %w", err)
	}
	return hex.EncodeToString(buf), nil
}

// upsertEnvValues sets each key in updates to its given value inside the env
// file at absPath, preserving every other line (comments, ordering, unrelated
// keys) exactly as-is. If absPath doesn't exist yet but a sibling
// .env.example does, the example file seeds the initial content (so header
// comments and documented-but-unset keys survive) before updates are
// applied. Appends any key with no existing line. Writes with 0600
// permissions on create; an existing file keeps its current permissions.
func upsertEnvValues(absPath string, updates map[string]string) error {
	data, err := os.ReadFile(absPath)
	if os.IsNotExist(err) {
		examplePath := filepath.Join(filepath.Dir(absPath), ".env.example")
		if exampleData, exampleErr := os.ReadFile(examplePath); exampleErr == nil {
			data = exampleData
		}
	} else if err != nil {
		return err
	}

	var lines []string
	if len(data) > 0 {
		lines = strings.Split(string(data), "\n")
	}

	remaining := make(map[string]string, len(updates))
	for k, v := range updates {
		remaining[k] = v
	}

	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		if trimmed == "" || strings.HasPrefix(trimmed, "#") {
			continue
		}
		key, _, ok := strings.Cut(trimmed, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		if value, needsUpdate := remaining[key]; needsUpdate {
			lines[i] = key + "=" + value
			delete(remaining, key)
		}
	}

	for _, spec := range sortedKeys(updates) {
		value, stillMissing := remaining[spec]
		if !stillMissing {
			continue
		}
		if len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) != "" {
			lines = append(lines, "")
		}
		lines = append(lines, spec+"="+value)
	}

	content := strings.Join(lines, "\n")
	if !strings.HasSuffix(content, "\n") {
		content += "\n"
	}
	return os.WriteFile(absPath, []byte(content), 0o600)
}

// sortedKeys gives upsertEnvValues a deterministic append order (map
// iteration order is randomized in Go) so repeated runs produce a stable
// diff instead of shuffling newly-appended lines each time.
func sortedKeys(m map[string]string) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}
