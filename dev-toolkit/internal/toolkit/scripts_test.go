package toolkit

import (
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"testing"
)

func writeFile(t *testing.T, path string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatalf("mkdir for %s: %v", path, err)
	}
	if err := os.WriteFile(path, []byte("#!/usr/bin/env bash\n"), 0o755); err != nil {
		t.Fatalf("write %s: %v", path, err)
	}
}

func TestDiscoverScripts(t *testing.T) {
	repo := t.TempDir()
	writeFile(t, filepath.Join(repo, "scripts", "one.sh"))
	writeFile(t, filepath.Join(repo, "scripts", "two.py"))
	writeFile(t, filepath.Join(repo, "backend", "core", "run-dev.sh"))
	// Known-stale, explicitly hidden.
	writeFile(t, filepath.Join(repo, "backend", "core", "test-ai-chat.sh"))
	// Should be skipped: not a script extension.
	writeFile(t, filepath.Join(repo, "scripts", "notes.txt"))
	// Should be skipped: inside an excluded directory.
	writeFile(t, filepath.Join(repo, "scripts", "target", "compiled.sh"))
	// Outside every scriptRoots entry — must not be discovered.
	writeFile(t, filepath.Join(repo, "frontend", "unrelated.sh"))

	scripts, hidden, err := discoverScripts(repo)
	if err != nil {
		t.Fatalf("discoverScripts: %v", err)
	}
	if hidden != 1 {
		t.Errorf("expected 1 hidden script, got %d", hidden)
	}

	var got []string
	for _, s := range scripts {
		got = append(got, s.RelPath)
	}
	sort.Strings(got)

	want := []string{"backend/core/run-dev.sh", "scripts/one.sh", "scripts/two.py"}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("index %d: got %q, want %q", i, got[i], want[i])
		}
	}
}

func TestDiscoverScripts_MissingRootsAreSkippedGracefully(t *testing.T) {
	repo := t.TempDir() // none of scriptRoots exist here
	scripts, hidden, err := discoverScripts(repo)
	if err != nil {
		t.Fatalf("discoverScripts on an empty repo should not error: %v", err)
	}
	if len(scripts) != 0 || hidden != 0 {
		t.Errorf("expected no scripts and no hidden count, got scripts=%v hidden=%d", scripts, hidden)
	}
}

func TestFilterScripts(t *testing.T) {
	scripts := []scriptEntry{
		{RelPath: "backend/core/run-dev.sh", Ext: ".sh"},
		{RelPath: "scripts/generate_pr_review_docx.py", Ext: ".py"},
		{RelPath: "quality/Local_Scans/run-local-checks.sh", Ext: ".sh"},
	}

	got := filterScripts(scripts, "quality")
	if len(got) != 1 || got[0].RelPath != "quality/Local_Scans/run-local-checks.sh" {
		t.Errorf("expected only the quality script, got %v", got)
	}

	if got := filterScripts(scripts, "nonexistent-term"); len(got) != 0 {
		t.Errorf("expected no matches, got %v", got)
	}

	if got := filterScripts(scripts, ""); len(got) != len(scripts) {
		t.Errorf("expected an empty term to match everything, got %d of %d", len(got), len(scripts))
	}
}

func TestScriptCommand(t *testing.T) {
	sh, err := scriptCommand(scriptEntry{RelPath: "scripts/x.sh", Ext: ".sh"})
	if err != nil {
		t.Fatalf("scriptCommand .sh: %v", err)
	}
	if len(sh) != 2 || sh[0] != "bash" {
		t.Errorf("expected a bash invocation, got %v", sh)
	}

	py, err := scriptCommand(scriptEntry{RelPath: "scripts/x.py", Ext: ".py"})
	if err != nil {
		t.Fatalf("scriptCommand .py: %v", err)
	}
	wantPyFirst := "python3"
	if runtime.GOOS == "windows" {
		wantPyFirst = "py"
	}
	if py[0] != wantPyFirst {
		t.Errorf("expected %q as the interpreter on %s, got %v", wantPyFirst, runtime.GOOS, py)
	}

	if runtime.GOOS != "windows" {
		if _, err := scriptCommand(scriptEntry{RelPath: "scripts/x.bat", Ext: ".bat"}); err == nil {
			t.Error("expected an error running a .bat script on a non-Windows platform")
		}
	}

	if _, err := scriptCommand(scriptEntry{RelPath: "scripts/x.unknown", Ext: ".unknown"}); err == nil {
		t.Error("expected an error for an unsupported script extension")
	}
}
