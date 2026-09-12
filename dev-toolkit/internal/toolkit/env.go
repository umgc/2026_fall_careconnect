package toolkit

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

var sensitiveName = regexp.MustCompile(`(?i)(SECRET|PASSWORD|TOKEN|KEY|CREDENTIAL|PRIVATE)`)

type envFileValues struct {
	Path   string
	Found  bool
	Values map[string]string
}

// printEnvPreview shows exactly one resolved line per key in envVars — the
// value and source (a specific file, or "current shell") that will actually
// be used, in the same precedence order the rest of the toolkit uses (files
// in envFiles, in order, then the current shell) — never two separate
// sections a reader has to reconcile themselves. A key found nowhere prints
// as <unset>. When envVars is empty, falls back to dumping whatever each
// file actually contains (used by commands that preview a whole .env file
// rather than naming specific keys).
func (a *App) printEnvPreview(repoRoot string, envFiles, envVars []string) error {
	if len(envFiles) == 0 && len(envVars) == 0 {
		return nil
	}

	parsedFiles := make([]envFileValues, 0, len(envFiles))
	for _, rel := range envFiles {
		parsed, err := readEnvFile(filepath.Join(repoRoot, filepath.FromSlash(rel)), rel)
		if err != nil {
			return err
		}
		parsedFiles = append(parsedFiles, parsed)
	}

	fmt.Fprintln(a.out)
	fmt.Fprintln(a.out, "Environment preview:")

	for _, f := range parsedFiles {
		if !f.Found {
			fmt.Fprintf(a.out, "- %s: missing\n", f.Path)
		}
	}

	if len(envVars) == 0 {
		for _, f := range parsedFiles {
			if !f.Found {
				continue
			}
			for key, value := range f.Values {
				fmt.Fprintf(a.out, "  %s=%s (%s)\n", key, maskValue(key, value), f.Path)
			}
		}
		return nil
	}

	for _, key := range envVars {
		if value, source, ok := resolveEnvValue(parsedFiles, key); ok {
			fmt.Fprintf(a.out, "  %s: %s (%s)\n", key, maskValue(key, value), source)
		} else {
			fmt.Fprintf(a.out, "  %s: <unset>\n", key)
		}
	}
	return nil
}

// resolveEnvValue applies the same precedence the rest of the toolkit uses
// for a key that can come from more than one place: each file in order,
// then the current shell. Returns the value, a human-readable source label,
// and whether it was found at all.
func resolveEnvValue(files []envFileValues, key string) (value, source string, ok bool) {
	for _, f := range files {
		if !f.Found {
			continue
		}
		if v, present := f.Values[key]; present && v != "" {
			return v, f.Path, true
		}
	}
	if v, present := os.LookupEnv(key); present && v != "" {
		return v, "current shell", true
	}
	return "", "", false
}

func readEnvFile(absPath, displayPath string) (envFileValues, error) {
	file, err := os.Open(absPath)
	if os.IsNotExist(err) {
		return envFileValues{Path: displayPath, Found: false, Values: map[string]string{}}, nil
	}
	if err != nil {
		return envFileValues{}, err
	}
	defer file.Close()
	values, err := parseEnv(file)
	if err != nil {
		return envFileValues{}, fmt.Errorf("%s: %w", displayPath, err)
	}
	return envFileValues{Path: displayPath, Found: true, Values: values}, nil
}

func parseEnv(r io.Reader) (map[string]string, error) {
	values := map[string]string{}
	scanner := bufio.NewScanner(r)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "export ") {
			line = strings.TrimSpace(strings.TrimPrefix(line, "export "))
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		key = strings.TrimSpace(key)
		value = strings.TrimSpace(value)
		value = strings.Trim(value, `"'`)
		if key != "" {
			values[key] = value
		}
	}
	return values, scanner.Err()
}

func maskValue(key, value string) string {
	if value == "" {
		return "<empty>"
	}
	if sensitiveName.MatchString(key) {
		return "<set, masked>"
	}
	if len(value) > 120 {
		return value[:117] + "..."
	}
	return value
}
