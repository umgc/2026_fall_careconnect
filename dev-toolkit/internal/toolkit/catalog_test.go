package toolkit

import (
	"os"
	"strings"
	"testing"
)

func TestEmbeddedCatalogValid(t *testing.T) {
	catalog, err := LoadCatalog("")
	if err != nil {
		t.Fatalf("LoadCatalog: %v", err)
	}
	if len(catalog.Commands) < 10 {
		t.Fatalf("expected a useful command catalog, got %d commands", len(catalog.Commands))
	}
	for _, id := range []string{"backend.start", "quality.local", "infra.deploy.full", "scripts.browser"} {
		if _, ok := catalog.Find(id); !ok {
			t.Fatalf("expected command %s", id)
		}
	}
}

// TestEveryCommandHasCuratedPlatformSupport guards against a new catalog
// entry landing without hand-curating platform_support — see the field's doc
// comment on Command for what "native" vs "posix" means.
func TestEveryCommandHasCuratedPlatformSupport(t *testing.T) {
	catalog, err := LoadCatalog("")
	if err != nil {
		t.Fatalf("LoadCatalog: %v", err)
	}
	for _, cmd := range catalog.Commands {
		switch cmd.PlatformSupport {
		case "native", "posix":
			// curated
		default:
			t.Errorf("%s: platform_support must be curated as \"native\" or \"posix\", got %q",
				cmd.ID, cmd.PlatformSupport)
		}
	}
}

func TestCatalogValidate(t *testing.T) {
	base := Command{ID: "a", Title: "A", Category: "cat", Action: "status"}

	if err := (Catalog{Commands: []Command{base}}).Validate(); err != nil {
		t.Fatalf("expected a valid single-command catalog to pass, got: %v", err)
	}

	noID := base
	noID.ID = ""
	if err := (Catalog{Commands: []Command{noID}}).Validate(); err == nil {
		t.Fatal("expected an error for a command with no id")
	}

	dup := Catalog{Commands: []Command{base, base}}
	if err := dup.Validate(); err == nil {
		t.Fatal("expected an error for a duplicate command id")
	}

	noTitle := base
	noTitle.Title = ""
	if err := (Catalog{Commands: []Command{noTitle}}).Validate(); err == nil {
		t.Fatal("expected an error for a command with no title")
	}

	noCategory := base
	noCategory.Category = ""
	if err := (Catalog{Commands: []Command{noCategory}}).Validate(); err == nil {
		t.Fatal("expected an error for a command with no category")
	}

	noActionOrShell := base
	noActionOrShell.Action = ""
	if err := (Catalog{Commands: []Command{noActionOrShell}}).Validate(); err == nil {
		t.Fatal("expected an error for a command with neither action nor shell")
	}

	withShell := base
	withShell.Action = ""
	withShell.Shell = map[string][]string{"posix": {"bash", "x.sh"}}
	if err := (Catalog{Commands: []Command{withShell}}).Validate(); err != nil {
		t.Errorf("a command with only shell (no action) should be valid, got: %v", err)
	}
}

func TestStableCommandIDs(t *testing.T) {
	catalog := Catalog{Commands: []Command{
		{ID: "zzz.last"},
		{ID: "aaa.first"},
		{ID: "mmm.middle"},
	}}
	got := stableCommandIDs(catalog)
	want := []string{"aaa.first", "mmm.middle", "zzz.last"}
	if len(got) != len(want) {
		t.Fatalf("got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("index %d: got %q, want %q", i, got[i], want[i])
		}
	}
}

func TestCommandShell(t *testing.T) {
	key := platformKey()

	nativeCmd := Command{ID: "x", Shell: map[string][]string{
		"posix":   {"bash", "posix.sh"},
		"windows": {"cmd", "/C", "windows.bat"},
	}}
	argv, err := commandShell(nativeCmd)
	if err != nil {
		t.Fatalf("commandShell: %v", err)
	}
	want := nativeCmd.Shell[key]
	if strings.Join(argv, " ") != strings.Join(want, " ") {
		t.Errorf("expected the %s-specific argv %v, got %v", key, want, argv)
	}

	noShell := Command{ID: "y", Shell: map[string][]string{}}
	if _, err := commandShell(noShell); err == nil {
		t.Fatal("expected an error when a command declares no shell for this platform")
	}

	if key == "posix" {
		// posix-only command (no windows key at all) must still resolve on posix.
		posixOnly := Command{ID: "z", Shell: map[string][]string{"posix": {"bash", "z.sh"}}}
		argv, err := commandShell(posixOnly)
		if err != nil {
			t.Fatalf("commandShell posix-only on posix: %v", err)
		}
		if strings.Join(argv, " ") != "bash z.sh" {
			t.Errorf("got %v", argv)
		}
	}
}

func TestInputEffectiveDefault(t *testing.T) {
	const envKey = "CARECONNECT_TEST_EFFECTIVE_DEFAULT"
	os.Unsetenv(envKey)
	t.Cleanup(func() { os.Unsetenv(envKey) })

	withoutEnvVar := Input{Default: "static-default"}
	if got := withoutEnvVar.effectiveDefault(); got != "static-default" {
		t.Errorf("no DefaultEnvVar set: got %q, want %q", got, "static-default")
	}

	withUnsetEnvVar := Input{Default: "static-default", DefaultEnvVar: envKey}
	if got := withUnsetEnvVar.effectiveDefault(); got != "static-default" {
		t.Errorf("DefaultEnvVar unset in shell: got %q, want fallback %q", got, "static-default")
	}

	os.Setenv(envKey, "from-shell")
	withSetEnvVar := Input{Default: "static-default", DefaultEnvVar: envKey}
	if got := withSetEnvVar.effectiveDefault(); got != "from-shell" {
		t.Errorf("DefaultEnvVar set in shell: got %q, want %q", got, "from-shell")
	}

	os.Setenv(envKey, "")
	emptyEnvVar := Input{Default: "static-default", DefaultEnvVar: envKey}
	if got := emptyEnvVar.effectiveDefault(); got != "static-default" {
		t.Errorf("DefaultEnvVar set but empty: got %q, want fallback %q", got, "static-default")
	}
}

func TestMaskValue(t *testing.T) {
	if got := maskValue("SECURITY_JWT_SECRET", "abc123"); got != "<set, masked>" {
		t.Fatalf("secret was not masked: %q", got)
	}
	if got := maskValue("SERVER_PORT", "8080"); got != "8080" {
		t.Fatalf("non-sensitive value changed: %q", got)
	}
}

func TestParseEnv(t *testing.T) {
	values, err := parseEnv(strings.NewReader(`
# comment
export SERVER_PORT=8081
DB_PASSWORD="secret"
EMPTY=
`))
	if err != nil {
		t.Fatalf("parseEnv: %v", err)
	}
	if values["SERVER_PORT"] != "8081" {
		t.Fatalf("SERVER_PORT=%q", values["SERVER_PORT"])
	}
	if values["DB_PASSWORD"] != "secret" {
		t.Fatalf("DB_PASSWORD=%q", values["DB_PASSWORD"])
	}
	if values["EMPTY"] != "" {
		t.Fatalf("EMPTY=%q", values["EMPTY"])
	}
}

func TestRenderArgsSkipsBlank(t *testing.T) {
	got := renderArgs([]string{"--image-tag", "{{value}}"}, "")
	if len(got) != 0 {
		t.Fatalf("blank value should skip args, got %#v", got)
	}
	got = renderArgs([]string{"--image-tag", "{{value}}"}, "demo")
	if strings.Join(got, " ") != "--image-tag demo" {
		t.Fatalf("unexpected args %#v", got)
	}
}

func TestRunnableScriptFilter(t *testing.T) {
	if isRunnableScript("quality/Local_Scans/report/render_report/report_builder.py") {
		t.Fatal("render internals should not be script-browser entries")
	}
	if isRunnableScript("quality/ci/gate/parsers/bandit.py") {
		t.Fatal("parser modules should not be script-browser entries")
	}
	if !isRunnableScript("quality/Local_Scans/report/generate_report.py") {
		t.Fatal("quality report generator should be discoverable")
	}
	if !isRunnableScript("scripts/generate_pr_review_docx.py") {
		t.Fatal("top-level scripts should be discoverable")
	}
}
