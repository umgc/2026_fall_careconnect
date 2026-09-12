package toolkit

import "testing"

func TestResolveChoiceAnswer(t *testing.T) {
	input := Input{Choices: []string{"dev", "cfdemo", "staging", "prod"}}

	cases := []struct {
		name    string
		answer  string
		want    string
		wantErr bool
	}{
		{"first index", "1", "dev", false},
		{"last index", "4", "prod", false},
		{"literal match", "staging", "staging", false},
		{"index zero is invalid", "0", "", true},
		{"index out of range", "5", "", true},
		{"unknown literal", "nope", "", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := resolveChoiceAnswer(input, tc.answer)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected an error for answer %q, got value %q", tc.answer, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error for answer %q: %v", tc.answer, err)
			}
			if got != tc.want {
				t.Errorf("resolveChoiceAnswer(%q) = %q, want %q", tc.answer, got, tc.want)
			}
		})
	}
}

func TestStringMapFlagSet(t *testing.T) {
	m := stringMapFlag{}
	if err := m.Set("environment=dev"); err != nil {
		t.Fatalf("Set: %v", err)
	}
	if err := m.Set("ai_model=amazon.nova-lite-v1:0"); err != nil {
		t.Fatalf("Set: %v", err)
	}
	if m["environment"] != "dev" {
		t.Errorf("environment = %q, want dev", m["environment"])
	}
	if m["ai_model"] != "amazon.nova-lite-v1:0" {
		t.Errorf("ai_model = %q, want amazon.nova-lite-v1:0", m["ai_model"])
	}
}

func TestStringMapFlagSetRejectsMissingEquals(t *testing.T) {
	m := stringMapFlag{}
	if err := m.Set("no-equals-sign"); err == nil {
		t.Fatal("expected an error for a value with no '=', got nil")
	}
}

func TestStringMapFlagSetRejectsEmptyName(t *testing.T) {
	m := stringMapFlag{}
	if err := m.Set("=value"); err == nil {
		t.Fatal("expected an error for an empty name, got nil")
	}
}

func TestStringMapFlagSetAllowsEmptyValue(t *testing.T) {
	m := stringMapFlag{}
	if err := m.Set("image_tag="); err != nil {
		t.Fatalf("Set: %v", err)
	}
	if v, ok := m["image_tag"]; !ok || v != "" {
		t.Errorf("image_tag = (%q, %v), want (\"\", true)", v, ok)
	}
}
