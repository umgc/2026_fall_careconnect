package toolkit

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
)

type scriptEntry struct {
	RelPath string
	Ext     string
}

var scriptRoots = []string{
	"scripts",
	"backend/core",
	"quality",
	"cloudformation-fargate",
}

var hiddenScripts = map[string]string{
	"backend/core/test-ai-chat.sh": "known stale against current AI/auth endpoints",
}

func (a *App) scriptBrowser(repoRoot string) error {
	scripts, hidden, err := discoverScripts(repoRoot)
	if err != nil {
		return err
	}
	for {
		fmt.Fprintln(a.out)
		fmt.Fprintf(a.out, "Script browser (%d helper scripts", len(scripts))
		if hidden > 0 {
			fmt.Fprintf(a.out, ", %d hidden stale/unsafe", hidden)
		}
		fmt.Fprintln(a.out, ")")
		fmt.Fprintln(a.out, "Type a number, /search text, b to go back, or q to quit.")
		for i, script := range scripts {
			if i >= 40 {
				fmt.Fprintf(a.out, "... %d more scripts. Use /search to narrow the list.\n", len(scripts)-40)
				break
			}
			fmt.Fprintf(a.out, "%2d. %s\n", i+1, script.RelPath)
		}
		answer, err := a.promptLine("> ")
		if err != nil {
			if errors.Is(err, io.EOF) {
				return nil
			}
			return err
		}
		if answer == "b" || answer == "back" {
			return nil
		}
		if answer == "q" || answer == "quit" || answer == "exit" {
			return nil
		}
		list := scripts
		if strings.HasPrefix(answer, "/") {
			term := strings.ToLower(strings.TrimPrefix(answer, "/"))
			list = filterScripts(scripts, term)
			if len(list) == 0 {
				fmt.Fprintln(a.out, "No scripts matched.")
				continue
			}
			for i, script := range list {
				fmt.Fprintf(a.out, "%2d. %s\n", i+1, script.RelPath)
			}
			answer, err = a.prompt("Run which script? ", "")
			if err != nil {
				return err
			}
		}
		n, err := strconv.Atoi(answer)
		if err != nil || n < 1 || n > len(list) {
			fmt.Fprintln(a.out, "Choose a listed number, /search, b, or q.")
			continue
		}
		if err := a.runScript(repoRoot, list[n-1]); err != nil {
			fmt.Fprintf(a.err, "%v\n", err)
		}
		_ = a.wait()
	}
}

func discoverScripts(repoRoot string) ([]scriptEntry, int, error) {
	exts := map[string]bool{".sh": true, ".ps1": true, ".bat": true, ".py": true}
	var scripts []scriptEntry
	hidden := 0
	for _, root := range scriptRoots {
		absRoot := filepath.Join(repoRoot, filepath.FromSlash(root))
		if _, err := os.Stat(absRoot); err != nil {
			continue
		}
		err := filepath.WalkDir(absRoot, func(path string, d os.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if d.IsDir() {
				switch d.Name() {
				case ".git", "target", "build", ".dart_tool", "__pycache__", "tools", "render_report", "parsers":
					return filepath.SkipDir
				}
				return nil
			}
			ext := strings.ToLower(filepath.Ext(path))
			if !exts[ext] {
				return nil
			}
			if runtime.GOOS != "windows" && ext == ".bat" {
				return nil
			}
			rel, err := filepath.Rel(repoRoot, path)
			if err != nil {
				return err
			}
			rel = filepath.ToSlash(rel)
			if _, ok := hiddenScripts[rel]; ok {
				hidden++
				return nil
			}
			if !isRunnableScript(rel) {
				return nil
			}
			scripts = append(scripts, scriptEntry{RelPath: rel, Ext: ext})
			return nil
		})
		if err != nil {
			return nil, hidden, err
		}
	}
	sort.Slice(scripts, func(i, j int) bool { return scripts[i].RelPath < scripts[j].RelPath })
	return scripts, hidden, nil
}

func isRunnableScript(rel string) bool {
	base := filepath.Base(rel)
	if base == "__init__.py" {
		return false
	}
	if strings.HasPrefix(rel, "quality/ci/gate/") {
		switch rel {
		case "quality/ci/gate/gate.py",
			"quality/ci/gate/normalize.py",
			"quality/ci/gate/policy_engine.py",
			"quality/ci/gate/report/report.py",
			"quality/ci/gate/report/report_github.py":
			return true
		default:
			return false
		}
	}
	if strings.HasPrefix(rel, "quality/Local_Scans/report/") {
		switch rel {
		case "quality/Local_Scans/report/generate_report.py",
			"quality/Local_Scans/report/open_report.py":
			return true
		default:
			return false
		}
	}
	return true
}

func filterScripts(scripts []scriptEntry, term string) []scriptEntry {
	var out []scriptEntry
	for _, script := range scripts {
		if strings.Contains(strings.ToLower(script.RelPath), term) {
			out = append(out, script)
		}
	}
	return out
}

func (a *App) runScript(repoRoot string, script scriptEntry) error {
	argv, err := scriptCommand(script)
	if err != nil {
		return err
	}
	extra, err := a.prompt("Extra args (optional): ", "")
	if err != nil {
		return err
	}
	if extra != "" {
		argv = append(argv, strings.Fields(extra)...)
	}
	fmt.Fprintln(a.out)
	fmt.Fprintf(a.out, "Script: %s\n", script.RelPath)
	fmt.Fprintf(a.out, "Command: %s\n", shellQuote(argv))
	ok, err := a.confirm("Run this script?", false)
	if err != nil {
		return err
	}
	if !ok {
		fmt.Fprintln(a.out, "Skipped.")
		return nil
	}
	return runProcess(context.Background(), repoRoot, argv, a.out, a.err)
}

func scriptCommand(script scriptEntry) ([]string, error) {
	path := filepath.FromSlash(script.RelPath)
	switch script.Ext {
	case ".sh":
		return []string{"bash", path}, nil
	case ".ps1":
		if runtime.GOOS == "windows" {
			return []string{"powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path}, nil
		}
		return []string{"pwsh", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path}, nil
	case ".bat":
		if runtime.GOOS != "windows" {
			return nil, fmt.Errorf("batch scripts can only run on Windows")
		}
		return []string{"cmd", "/C", path}, nil
	case ".py":
		if runtime.GOOS == "windows" {
			return []string{"py", "-3", path}, nil
		}
		return []string{"python3", path}, nil
	default:
		return nil, fmt.Errorf("unsupported script extension %q", script.Ext)
	}
}
