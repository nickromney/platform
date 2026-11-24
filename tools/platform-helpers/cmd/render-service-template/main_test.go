package main

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func sampleValues() Values {
	return Values{
		Name:         "orders",
		Owner:        "group:default/team-dolphin",
		Team:         "dolphin",
		Description:  "Orders service",
		FrontendPort: 8080,
		BackendPort:  9090,
		Environments: []string{"dev", "uat"},
	}
}

func TestRenderSubstitutesScalarValues(t *testing.T) {
	got, err := Render("name: ${{ values.name }}\nport: ${{values.backendPort}}\n", sampleValues())
	if err != nil {
		t.Fatal(err)
	}
	if want := "name: orders\nport: 9090\n"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestRenderLoopOverYAMLListLeavesNoBlankLines(t *testing.T) {
	text := "names:\n  {% for environment in values.environments %}\n  - ${{ environment }}\n  {% endfor %}\nnext: 1\n"
	got, err := Render(text, sampleValues())
	if err != nil {
		t.Fatal(err)
	}
	if want := "names:\n  - dev\n  - uat\nnext: 1\n"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestRenderSeparatorOnlyBetweenIterations(t *testing.T) {
	text := "{% for environment in values.environments %}\nname: ${{ values.name }}-${{ environment }}\n{% if not loop.last %}\n---\n{% endif %}\n{% endfor %}\n"
	got, err := Render(text, sampleValues())
	if err != nil {
		t.Fatal(err)
	}
	if want := "name: orders-dev\n---\nname: orders-uat\n"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}

	single := sampleValues()
	single.Environments = []string{"dev"}
	got, err = Render(text, single)
	if err != nil {
		t.Fatal(err)
	}
	if want := "name: orders-dev\n"; got != want {
		t.Fatalf("single environment: got %q, want %q", got, want)
	}
}

func TestRenderLeavesShellVariablesAlone(t *testing.T) {
	text := "run: echo ${APP_NAME} ${REVIEW_SLUG}\n"
	got, err := Render(text, sampleValues())
	if err != nil {
		t.Fatal(err)
	}
	if got != text {
		t.Fatalf("got %q, want unchanged", got)
	}
}

func TestRenderRejectsUnknownSyntax(t *testing.T) {
	cases := map[string]string{
		"unknown value":          "x: ${{ values.missing }}\n",
		"unknown expression":     "x: ${{ parameters.name }}\n",
		"unknown tag":            "{% raw %}x{% endraw %}\n",
		"environment outside":    "x: ${{ environment }}\n",
		"if outside loop":        "{% if not loop.last %}---{% endif %}\n",
		"unterminated for":       "{% for environment in values.environments %}\nx\n",
		"unterminated if in for": "{% for environment in values.environments %}{% if not loop.last %}x{% endfor %}\n",
	}
	for name, text := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := Render(text, sampleValues()); err == nil {
				t.Fatalf("expected an error for %q", text)
			}
		})
	}
}

func TestValidateMatchesTheOldFormRules(t *testing.T) {
	bad := []func(*Values){
		func(v *Values) { v.Name = "Orders" },
		func(v *Values) { v.Name = "-orders" },
		func(v *Values) { v.Team = "team_dolphin" },
		func(v *Values) { v.Owner = " " },
		func(v *Values) { v.FrontendPort = 80 },
		func(v *Values) { v.BackendPort = 70000 },
		func(v *Values) { v.Environments = nil },
		func(v *Values) { v.Environments = []string{"prod"} },
		func(v *Values) { v.Environments = []string{"dev", "dev"} },
	}
	for i, mutate := range bad {
		v := sampleValues()
		mutate(&v)
		if err := v.Validate(); err == nil {
			t.Errorf("case %d: expected a validation error for %+v", i, v)
		}
	}
	if err := sampleValues().Validate(); err != nil {
		t.Fatalf("sample values should validate: %v", err)
	}
}

func repoTemplateDir(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("cannot locate test file")
	}
	return filepath.Join(filepath.Dir(file), "..", "..", "..", "..", "templates", "platform-service", "content")
}

func TestRenderTreeRendersTheRealTemplate(t *testing.T) {
	out := filepath.Join(t.TempDir(), "orders")
	if err := RenderTree(repoTemplateDir(t), out, sampleValues()); err != nil {
		t.Fatal(err)
	}

	err := filepath.WalkDir(out, func(path string, entry os.DirEntry, err error) error {
		if err != nil || entry.IsDir() {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		text := string(data)
		if strings.Contains(text, "${{") || strings.Contains(text, "{%") {
			t.Errorf("%s still holds template syntax", path)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	routes, err := os.ReadFile(filepath.Join(out, "kubernetes", "routing", "httproutes.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"name: orders-dev\n", "name: orders-uat\n", "\n---\n"} {
		if !strings.Contains(string(routes), want) {
			t.Errorf("httproutes.yaml is missing %q", want)
		}
	}
	if strings.HasSuffix(strings.TrimSpace(string(routes)), "---") {
		t.Error("httproutes.yaml ends with a document separator")
	}

	scrape, err := os.ReadFile(filepath.Join(out, "kubernetes", "observability", "prometheus-scrape.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(scrape), "              - dev\n              - uat\n") {
		t.Errorf("prometheus-scrape.yaml did not render the environment list:\n%s", scrape)
	}

	if _, err := os.Stat(filepath.Join(out, ".gitea", "workflows", "review-environment.yaml")); err != nil {
		t.Errorf("review workflow missing from render: %v", err)
	}
}

func TestRenderTreeRefusesAnExistingOutputDirectory(t *testing.T) {
	out := t.TempDir()
	if err := RenderTree(repoTemplateDir(t), out, sampleValues()); err == nil {
		t.Fatal("expected RenderTree to refuse an existing directory")
	}
}
