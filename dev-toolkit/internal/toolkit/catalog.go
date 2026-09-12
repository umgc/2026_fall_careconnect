package toolkit

import (
	"embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
)

//go:embed catalog.json
var catalogFS embed.FS

type Catalog struct {
	Version  int       `json:"version"`
	Commands []Command `json:"commands"`
}

type Command struct {
	ID                  string              `json:"id"`
	Title               string              `json:"title"`
	Category            string              `json:"category"`
	Summary             string              `json:"summary"`
	WorkingDir          string              `json:"working_dir"`
	Action              string              `json:"action"`
	Shell               map[string][]string `json:"shell"`
	Inputs              []Input             `json:"inputs"`
	EnvFiles            []string            `json:"env_files"`
	EnvVars             []string            `json:"env_vars"`
	Requires            []string            `json:"requires"`
	Warnings            []string            `json:"warnings"`
	AllowExtraArgs      bool                `json:"allow_extra_args"`
	GenerateSecretsFile string              `json:"generate_secrets_file"`
	GenerateSecrets     []SecretSpec        `json:"generate_secrets"`
	// PlatformSupport is hand-curated documentation, not an automated
	// platform gate — every entry still runs wherever its shell/action
	// actually works. "native": a true equivalent exists per platform (a
	// real .ps1/.bat, a python script, or a native Go action). "posix":
	// the windows shell array just re-invokes the same bash script, so
	// Windows users need Git Bash (see the entry's warnings for the
	// specific caveat) — curate this by hand when adding new entries.
	PlatformSupport string `json:"platform_support"`
}

// SecretSpec describes one env var this command can offer to generate a
// random value for (see ensureGeneratedSecrets) when it's unset both in the
// current shell and in GenerateSecretsFile.
type SecretSpec struct {
	Key   string `json:"key"`
	Bytes int    `json:"bytes"`
}

type Input struct {
	Name    string   `json:"name"`
	Label   string   `json:"label"`
	Type    string   `json:"type"`
	Default string   `json:"default"`
	Choices []string `json:"choices"`
	// DefaultEnvVar, if set and non-empty in the current shell, overrides
	// Default at prompt time — e.g. an AWS profile/region input can default
	// to whatever the user already has exported (AWS_PROFILE, AWS_REGION)
	// instead of a hardcoded value baked into the catalog. Falls back to
	// Default when the env var is unset or empty.
	DefaultEnvVar string              `json:"default_env_var"`
	Args          map[string][]string `json:"args"`
	WhenTrue      map[string][]string `json:"when_true"`
	WhenFalse     map[string][]string `json:"when_false"`
}

// effectiveDefault resolves DefaultEnvVar (if set and non-empty in the
// current environment) over the static Default.
func (i Input) effectiveDefault() string {
	if i.DefaultEnvVar != "" {
		if v := os.Getenv(i.DefaultEnvVar); v != "" {
			return v
		}
	}
	return i.Default
}

func LoadCatalog(path string) (Catalog, error) {
	var data []byte
	var err error
	if path != "" {
		data, err = os.ReadFile(path)
	} else {
		data, err = catalogFS.ReadFile("catalog.json")
	}
	if err != nil {
		return Catalog{}, err
	}

	var catalog Catalog
	if err := json.Unmarshal(data, &catalog); err != nil {
		return Catalog{}, err
	}
	if err := catalog.Validate(); err != nil {
		return Catalog{}, err
	}
	return catalog, nil
}

func (c Catalog) Validate() error {
	seen := map[string]bool{}
	for i, cmd := range c.Commands {
		if strings.TrimSpace(cmd.ID) == "" {
			return fmt.Errorf("catalog command %d has no id", i)
		}
		if seen[cmd.ID] {
			return fmt.Errorf("duplicate command id %q", cmd.ID)
		}
		seen[cmd.ID] = true
		if strings.TrimSpace(cmd.Title) == "" {
			return fmt.Errorf("catalog command %q has no title", cmd.ID)
		}
		if strings.TrimSpace(cmd.Category) == "" {
			return fmt.Errorf("catalog command %q has no category", cmd.ID)
		}
		if cmd.Action == "" && len(cmd.Shell) == 0 {
			return fmt.Errorf("catalog command %q has neither action nor shell", cmd.ID)
		}
	}
	return nil
}

func (c Catalog) Find(id string) (Command, bool) {
	for _, cmd := range c.Commands {
		if cmd.ID == id {
			return cmd, true
		}
	}
	return Command{}, false
}

func (c Catalog) Categories() []string {
	seen := map[string]bool{}
	var categories []string
	for _, cmd := range c.Commands {
		if !seen[cmd.Category] {
			seen[cmd.Category] = true
			categories = append(categories, cmd.Category)
		}
	}
	return categories
}

func (c Catalog) CommandsInCategory(category string) []Command {
	var out []Command
	for _, cmd := range c.Commands {
		if cmd.Category == category {
			out = append(out, cmd)
		}
	}
	return out
}

func (c Catalog) Search(term string) []Command {
	term = strings.ToLower(strings.TrimSpace(term))
	if term == "" {
		return nil
	}
	var out []Command
	for _, cmd := range c.Commands {
		haystack := strings.ToLower(cmd.ID + " " + cmd.Title + " " + cmd.Category + " " + cmd.Summary)
		if strings.Contains(haystack, term) {
			out = append(out, cmd)
		}
	}
	return out
}

func platformKey() string {
	if runtime.GOOS == "windows" {
		return "windows"
	}
	return "posix"
}

func commandShell(cmd Command) ([]string, error) {
	key := platformKey()
	if argv := cmd.Shell[key]; len(argv) > 0 {
		return append([]string(nil), argv...), nil
	}
	if argv := cmd.Shell["posix"]; key != "windows" && len(argv) > 0 {
		return append([]string(nil), argv...), nil
	}
	return nil, fmt.Errorf("command %q has no shell command for %s", cmd.ID, key)
}

func renderArgs(args []string, value string) []string {
	if value == "" {
		return nil
	}
	out := make([]string, 0, len(args))
	for _, arg := range args {
		out = append(out, strings.ReplaceAll(arg, "{{value}}", value))
	}
	return out
}

func stableCommandIDs(c Catalog) []string {
	ids := make([]string, 0, len(c.Commands))
	for _, cmd := range c.Commands {
		ids = append(ids, cmd.ID)
	}
	sort.Strings(ids)
	return ids
}

func FindRepoRoot(start string) (string, error) {
	dir, err := filepath.Abs(start)
	if err != nil {
		return "", err
	}
	for {
		if exists(filepath.Join(dir, "backend", "core")) &&
			exists(filepath.Join(dir, "quality")) &&
			exists(filepath.Join(dir, "cloudformation-fargate")) {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("could not find CareConnect repo root from %s", start)
		}
		dir = parent
	}
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
