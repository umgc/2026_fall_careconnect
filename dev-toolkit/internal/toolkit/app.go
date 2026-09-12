package toolkit

import (
	"bufio"
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

type App struct {
	in  *bufio.Reader
	out io.Writer
	err io.Writer
}

type runOptions struct {
	dryRun    bool
	noConfirm bool
	presets   map[string]string
}

var errQuit = errors.New("quit")

// stringMapFlag collects repeated -set name=value flags into a map so
// specific catalog inputs can be pre-filled and skip their prompt.
type stringMapFlag map[string]string

func (m stringMapFlag) String() string {
	if len(m) == 0 {
		return ""
	}
	parts := make([]string, 0, len(m))
	for k, v := range m {
		parts = append(parts, k+"="+v)
	}
	return strings.Join(parts, ",")
}

func (m stringMapFlag) Set(raw string) error {
	name, value, ok := strings.Cut(raw, "=")
	if !ok || name == "" {
		return fmt.Errorf("invalid -set value %q, expected name=value", raw)
	}
	m[name] = value
	return nil
}

func NewApp(in io.Reader, out, err io.Writer) *App {
	return &App{
		in:  bufio.NewReader(in),
		out: out,
		err: err,
	}
}

func (a *App) Run(args []string) error {
	fs := flag.NewFlagSet("careconnect-dev", flag.ContinueOnError)
	fs.SetOutput(a.err)
	var (
		catalogPath string
		repoArg     string
		runID       string
		dryRunID    string
		list        bool
		health      bool
		noConfirm   bool
	)
	presets := stringMapFlag{}
	fs.StringVar(&catalogPath, "catalog", "", "optional path to a catalog.json override")
	fs.StringVar(&repoArg, "repo", "", "repository root override")
	fs.StringVar(&runID, "run", "", "run a command by id")
	fs.StringVar(&dryRunID, "dry-run", "", "preview a command by id without running it")
	fs.BoolVar(&list, "list", false, "list command ids")
	fs.BoolVar(&health, "health", false, "check backend health")
	fs.BoolVar(&noConfirm, "yes", false, "skip confirmation prompts for --run")
	fs.Var(presets, "set", "pre-fill a catalog input and skip its prompt, as name=value (repeatable; use with --run/--dry-run)")
	if err := fs.Parse(args); err != nil {
		return err
	}

	repoRoot, err := resolveRepoRoot(repoArg)
	if err != nil {
		return err
	}
	catalog, err := LoadCatalog(catalogPath)
	if err != nil {
		return fmt.Errorf("load catalog: %w", err)
	}

	switch {
	case list:
		for _, id := range stableCommandIDs(catalog) {
			cmd, _ := catalog.Find(id)
			platform := cmd.PlatformSupport
			if platform == "" {
				platform = "?"
			}
			fmt.Fprintf(a.out, "%-30s [%-6s] %s\n", id, platform, cmd.Title)
		}
		return nil
	case health:
		return a.printHealth(repoRoot)
	case dryRunID != "":
		cmd, ok := catalog.Find(dryRunID)
		if !ok {
			return fmt.Errorf("unknown command id %q", dryRunID)
		}
		return a.runCommand(repoRoot, cmd, runOptions{dryRun: true, presets: presets})
	case runID != "":
		cmd, ok := catalog.Find(runID)
		if !ok {
			return fmt.Errorf("unknown command id %q", runID)
		}
		return a.runCommand(repoRoot, cmd, runOptions{noConfirm: noConfirm, presets: presets})
	default:
		return a.interactive(repoRoot, catalog)
	}
}

func resolveRepoRoot(arg string) (string, error) {
	if arg != "" {
		return filepath.Abs(arg)
	}
	if env := os.Getenv("CARECONNECT_REPO_ROOT"); env != "" {
		return filepath.Abs(env)
	}
	wd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	return FindRepoRoot(wd)
}

func (a *App) interactive(repoRoot string, catalog Catalog) error {
	for {
		fmt.Fprintln(a.out)
		fmt.Fprintln(a.out, "CareConnect Dev Toolkit")
		fmt.Fprintf(a.out, "Repo: %s\n", repoRoot)
		fmt.Fprintf(a.out, "Platform: %s\n", platformKey())
		fmt.Fprintln(a.out)

		categories := catalog.Categories()
		for i, category := range categories {
			fmt.Fprintf(a.out, "%2d. %s\n", i+1, category)
		}
		fmt.Fprintln(a.out)
		fmt.Fprintln(a.out, "Type a number, /search text, h for health, or q to quit.")

		answer, err := a.prompt("> ", "")
		if err != nil {
			return err
		}
		switch {
		case answer == "q" || answer == "quit" || answer == "exit":
			return nil
		case answer == "h" || answer == "health":
			if err := a.printHealth(repoRoot); err != nil {
				fmt.Fprintf(a.err, "%v\n", err)
			}
			_ = a.wait()
		case strings.HasPrefix(answer, "/"):
			if err := a.searchMenu(repoRoot, catalog, strings.TrimPrefix(answer, "/")); err != nil {
				return err
			}
		default:
			n, err := strconv.Atoi(answer)
			if err != nil || n < 1 || n > len(categories) {
				fmt.Fprintln(a.out, "Choose a listed number, /search, h, or q.")
				continue
			}
			if err := a.commandMenu(repoRoot, catalog.CommandsInCategory(categories[n-1])); err != nil {
				if errors.Is(err, errQuit) {
					return nil
				}
				return err
			}
		}
	}
}

func (a *App) commandMenu(repoRoot string, commands []Command) error {
	for {
		fmt.Fprintln(a.out)
		if len(commands) == 0 {
			fmt.Fprintln(a.out, "No commands in this category.")
			return nil
		}
		fmt.Fprintf(a.out, "%s\n", commands[0].Category)
		for i, cmd := range commands {
			fmt.Fprintf(a.out, "%2d. %s\n", i+1, cmd.Title)
			fmt.Fprintf(a.out, "    %s\n", cmd.Summary)
		}
		fmt.Fprintln(a.out)
		fmt.Fprintln(a.out, "Type a number, b to go back, or q to quit.")
		answer, err := a.prompt("> ", "")
		if err != nil {
			return err
		}
		if answer == "b" || answer == "back" {
			return nil
		}
		if answer == "q" || answer == "quit" || answer == "exit" {
			return errQuit
		}
		n, err := strconv.Atoi(answer)
		if err != nil || n < 1 || n > len(commands) {
			fmt.Fprintln(a.out, "Choose a listed number, b, or q.")
			continue
		}
		if err := a.runCommand(repoRoot, commands[n-1], runOptions{}); err != nil {
			if errors.Is(err, io.EOF) {
				return err
			}
			fmt.Fprintf(a.err, "%v\n", err)
		}
		_ = a.wait()
	}
}

func (a *App) searchMenu(repoRoot string, catalog Catalog, term string) error {
	results := catalog.Search(term)
	if len(results) == 0 {
		fmt.Fprintln(a.out, "No matching commands.")
		return nil
	}
	return a.commandMenu(repoRoot, results)
}

func (a *App) runCommand(repoRoot string, cmd Command, opts runOptions) error {
	switch cmd.Action {
	case "health":
		return a.printHealth(repoRoot)
	case "register-patient":
		return a.registerPatient(repoRoot)
	case "browse-scripts":
		return a.scriptBrowser(repoRoot)
	case "status":
		return a.printStatus(repoRoot)
	}

	argv, err := commandShell(cmd)
	if err != nil {
		return err
	}
	extra, err := a.collectInputArgs(cmd, opts.presets)
	if err != nil {
		return err
	}
	argv = append(argv, extra...)

	fmt.Fprintln(a.out)
	fmt.Fprintf(a.out, "%s\n", cmd.Title)
	fmt.Fprintf(a.out, "%s\n", cmd.Summary)
	if len(cmd.Warnings) > 0 {
		fmt.Fprintln(a.out)
		fmt.Fprintln(a.out, "Warnings:")
		for _, warning := range cmd.Warnings {
			fmt.Fprintf(a.out, "- %s\n", warning)
		}
	}
	if opts.dryRun {
		// Dry-run stays a pure, side-effect-free preview: warn if secrets are
		// missing, but never prompt or write a file.
		if err := a.warnMissingSecrets(repoRoot, cmd); err != nil {
			return err
		}
	} else {
		// Offers to fill in any missing secrets before the preview below, so
		// the preview reflects what will actually run.
		if err := a.ensureGeneratedSecrets(repoRoot, cmd); err != nil {
			return err
		}
	}
	if err := a.printEnvPreview(repoRoot, cmd.EnvFiles, cmd.EnvVars); err != nil {
		fmt.Fprintf(a.err, "env preview: %v\n", err)
	}

	workDir := repoRoot
	if cmd.WorkingDir != "" && cmd.WorkingDir != "." {
		workDir = filepath.Join(repoRoot, filepath.FromSlash(cmd.WorkingDir))
	}
	fmt.Fprintln(a.out)
	fmt.Fprintf(a.out, "Working directory: %s\n", workDir)
	fmt.Fprintf(a.out, "Command: %s\n", shellQuote(argv))

	missing := missingRequiredTools(cmd.Requires)
	if len(missing) > 0 {
		fmt.Fprintf(a.out, "Missing tools: %s\n", strings.Join(missing, ", "))
	}
	if opts.dryRun {
		return nil
	}
	if !opts.noConfirm {
		ok, err := a.confirm("Run this command?", false)
		if err != nil {
			return err
		}
		if !ok {
			fmt.Fprintln(a.out, "Skipped.")
			return nil
		}
	}
	return runProcess(context.Background(), workDir, argv, a.out, a.err)
}

func (a *App) collectInputArgs(cmd Command, presets map[string]string) ([]string, error) {
	var all []string
	key := platformKey()
	consumed := make(map[string]bool, len(presets))
	for _, input := range cmd.Inputs {
		preset, isPreset := presets[input.Name]
		if isPreset {
			consumed[input.Name] = true
		}
		switch input.Type {
		case "choice":
			var value string
			var err error
			if isPreset {
				value, err = resolveChoiceAnswer(input, preset)
				if err != nil {
					return nil, fmt.Errorf("-set %s: %w", input.Name, err)
				}
				fmt.Fprintf(a.out, "%s: %s (preset)\n", input.Label, value)
			} else {
				value, err = a.promptChoice(input)
			}
			if err != nil {
				return nil, err
			}
			all = append(all, renderArgs(input.Args[key], value)...)
		case "bool":
			var value bool
			if isPreset {
				parsed, err := strconv.ParseBool(preset)
				if err != nil {
					return nil, fmt.Errorf("-set %s: invalid bool %q", input.Name, preset)
				}
				value = parsed
				fmt.Fprintf(a.out, "%s: %v (preset)\n", input.Label, value)
			} else {
				defaultValue := strings.EqualFold(input.effectiveDefault(), "true")
				confirmed, err := a.confirm(input.Label, defaultValue)
				if err != nil {
					return nil, err
				}
				value = confirmed
			}
			if value {
				all = append(all, input.WhenTrue[key]...)
			} else {
				all = append(all, input.WhenFalse[key]...)
			}
		default:
			var value string
			var err error
			if isPreset {
				value = preset
				fmt.Fprintf(a.out, "%s: %s (preset)\n", input.Label, value)
			} else {
				value, err = a.prompt(input.Label+": ", input.effectiveDefault())
			}
			if err != nil {
				return nil, err
			}
			all = append(all, renderArgs(input.Args[key], value)...)
		}
	}
	if cmd.AllowExtraArgs {
		if preset, isPreset := presets["extra_args"]; isPreset {
			consumed["extra_args"] = true
			fmt.Fprintf(a.out, "Extra args: %s (preset)\n", preset)
			all = append(all, strings.Fields(preset)...)
		} else {
			value, err := a.prompt("Extra args (optional): ", "")
			if err != nil {
				return nil, err
			}
			all = append(all, strings.Fields(value)...)
		}
	}
	for name := range presets {
		if !consumed[name] {
			fmt.Fprintf(a.err, "warning: -set %s does not match any input for this command\n", name)
		}
	}
	return all, nil
}

// resolveChoiceAnswer accepts either a 1-based index into input.Choices or
// the literal choice text, matching what promptChoice accepts interactively.
func resolveChoiceAnswer(input Input, answer string) (string, error) {
	if n, err := strconv.Atoi(answer); err == nil && n >= 1 && n <= len(input.Choices) {
		return input.Choices[n-1], nil
	}
	for _, choice := range input.Choices {
		if answer == choice {
			return answer, nil
		}
	}
	return "", fmt.Errorf("invalid choice %q", answer)
}

func (a *App) promptChoice(input Input) (string, error) {
	def := input.effectiveDefault()
	fmt.Fprintf(a.out, "%s", input.Label)
	if def != "" {
		fmt.Fprintf(a.out, " [%s]", def)
	}
	fmt.Fprintln(a.out)
	for i, choice := range input.Choices {
		fmt.Fprintf(a.out, "  %d. %s\n", i+1, choice)
	}
	answer, err := a.prompt("> ", def)
	if err != nil {
		return "", err
	}
	return resolveChoiceAnswer(input, answer)
}

func (a *App) prompt(label, defaultValue string) (string, error) {
	if defaultValue != "" {
		fmt.Fprintf(a.out, "%s[%s] ", label, defaultValue)
	} else {
		fmt.Fprint(a.out, label)
	}
	line, err := a.in.ReadString('\n')
	if err != nil && !errors.Is(err, io.EOF) {
		return "", err
	}
	answer := strings.TrimSpace(line)
	if answer == "" {
		return defaultValue, nil
	}
	return answer, nil
}

// promptLine reads one line without defaulting on EOF — unlike prompt, which
// treats EOF as "use the default" (correct for a fixed sequence of distinct
// wizard fields, where each field should still get its own default even if
// stdin runs out partway through). Callers that loop on the SAME prompt
// repeatedly (e.g. an interactive menu) need to distinguish real EOF from a
// legitimate empty answer, since prompt's EOF-swallowing would otherwise
// make an exhausted input source look identical to "try again" forever.
func (a *App) promptLine(label string) (string, error) {
	fmt.Fprint(a.out, label)
	line, err := a.in.ReadString('\n')
	if err != nil {
		if errors.Is(err, io.EOF) {
			return "", io.EOF
		}
		return "", err
	}
	return strings.TrimSpace(line), nil
}

func (a *App) confirm(label string, defaultValue bool) (bool, error) {
	suffix := "y/N"
	if defaultValue {
		suffix = "Y/n"
	}
	answer, err := a.prompt(fmt.Sprintf("%s [%s] ", label, suffix), "")
	if err != nil {
		return false, err
	}
	if answer == "" {
		return defaultValue, nil
	}
	switch strings.ToLower(answer) {
	case "y", "yes", "true", "1":
		return true, nil
	case "n", "no", "false", "0":
		return false, nil
	default:
		return false, fmt.Errorf("expected yes or no, got %q", answer)
	}
}

func (a *App) wait() error {
	_, err := a.prompt("Press Enter to continue.", "")
	if errors.Is(err, io.EOF) {
		return nil
	}
	return err
}

func (a *App) printHealth(repoRoot string) error {
	baseURL := backendBaseURL(repoRoot)
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	status, body, err := CheckBackendHealth(ctx, baseURL)
	if err != nil {
		return fmt.Errorf("backend health %s: %w", baseURL, err)
	}
	fmt.Fprintf(a.out, "Backend health: %s -> HTTP %d\n", baseURL, status)
	if body != "" {
		fmt.Fprintln(a.out, body)
	}
	return nil
}

func (a *App) printStatus(repoRoot string) error {
	fmt.Fprintf(a.out, "Repo root: %s\n", repoRoot)
	fmt.Fprintf(a.out, "Platform: %s\n", platformKey())
	if branch := gitBranch(repoRoot); branch != "" {
		fmt.Fprintf(a.out, "Git branch: %s\n", branch)
	}
	fmt.Fprintln(a.out)
	tools := []string{"go", "git", "docker", "java", "mvn", "flutter", "python3", "aws", "bash", "pwsh", "powershell.exe"}
	for _, tool := range tools {
		if path, ok := lookPath(tool); ok {
			fmt.Fprintf(a.out, "%-15s %s\n", tool, path)
		} else {
			fmt.Fprintf(a.out, "%-15s missing\n", tool)
		}
	}
	fmt.Fprintln(a.out)
	if err := a.printHealth(repoRoot); err != nil {
		fmt.Fprintf(a.out, "Backend health: %v\n", err)
	}
	return nil
}

func gitBranch(repoRoot string) string {
	cmd := exec.Command("git", "-C", repoRoot, "branch", "--show-current")
	out, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

func missingRequiredTools(tools []string) []string {
	var missing []string
	for _, tool := range tools {
		candidates := []string{tool}
		if tool == "powershell" {
			candidates = []string{"pwsh", "powershell", "powershell.exe"}
		}
		found := false
		for _, candidate := range candidates {
			if _, ok := lookPath(candidate); ok {
				found = true
				break
			}
		}
		if !found {
			missing = append(missing, tool)
		}
	}
	return missing
}

func lookPath(name string) (string, bool) {
	path, err := exec.LookPath(name)
	return path, err == nil
}
