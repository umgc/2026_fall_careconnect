package toolkit

import "testing"

func TestShellQuote(t *testing.T) {
	cases := []struct {
		name string
		argv []string
		want string
	}{
		{"simple", []string{"bash", "run-dev.sh"}, "bash run-dev.sh"},
		{"empty arg", []string{"echo", ""}, `echo ""`},
	}
	for _, tc := range cases {
		if got := shellQuote(tc.argv); got != tc.want {
			t.Errorf("%s: got %q, want %q", tc.name, got, tc.want)
		}
	}

	// A quoted argument must round-trip its meaning: the space must end up
	// inside a single quoted token, not split into two argv entries.
	quoted := quoteArg("hello world")
	if quoted == "hello world" {
		t.Errorf("expected an argument containing a space to be quoted, got %q", quoted)
	}

	// An argument with no special characters must be left bare (readable
	// preview output), not needlessly quoted.
	if got := quoteArg("plain-arg"); got != "plain-arg" {
		t.Errorf("expected a plain argument to stay unquoted, got %q", got)
	}
}

func TestMissingRequiredTools(t *testing.T) {
	// "go" must exist in the environment running this test.
	if missing := missingRequiredTools([]string{"go"}); len(missing) != 0 {
		t.Errorf("expected 'go' to be found on PATH, got missing=%v", missing)
	}

	fake := "definitely-not-a-real-tool-xyz"
	missing := missingRequiredTools([]string{fake})
	if len(missing) != 1 || missing[0] != fake {
		t.Errorf("expected %q to be reported missing, got %v", fake, missing)
	}

	mixed := missingRequiredTools([]string{"go", fake})
	if len(mixed) != 1 || mixed[0] != fake {
		t.Errorf("expected only %q to be reported missing from a mixed list, got %v", fake, mixed)
	}

	if missing := missingRequiredTools(nil); len(missing) != 0 {
		t.Errorf("expected no missing tools for an empty requirement list, got %v", missing)
	}
}
