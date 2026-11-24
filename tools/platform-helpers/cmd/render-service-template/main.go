// Command render-service-template renders templates/platform-service into a
// directory ready to push as a new Gitea repository.
//
// It understands exactly the template syntax the platform-service content
// uses, and fails on anything else so a new construct cannot slip through
// unrendered:
//
//	${{ values.<key> }}                              a scalar value
//	{% for environment in values.environments %}     repeat a block per environment
//	${{ environment }}                               the current environment, inside the loop
//	{% if not loop.last %} ... {% endif %}           text between iterations, inside the loop
//
// A line holding only a tag disappears from the output, so loops over YAML
// list items render without stray blank lines.
package main

import (
	"errors"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

var (
	dnsLabel = regexp.MustCompile(`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`)

	forOpen    = "{% for environment in values.environments %}"
	forClose   = "{% endfor %}"
	ifNotLast  = "{% if not loop.last %}"
	ifClose    = "{% endif %}"
	anyTag     = regexp.MustCompile(`\{%.*?%\}`)
	anyExpr    = regexp.MustCompile(`\$\{\{.*?\}\}`)
	valueExpr  = regexp.MustCompile(`\$\{\{\s*values\.([A-Za-z]+)\s*\}\}`)
	envExpr    = regexp.MustCompile(`\$\{\{\s*environment\s*\}\}`)
	tagOnlyRow = regexp.MustCompile(`^[ \t]*\{%.*?%\}[ \t]*$`)
)

// Values are the inputs the template can reference.
type Values struct {
	Name         string
	Owner        string
	Team         string
	Description  string
	FrontendPort int
	BackendPort  int
	Environments []string
}

func (v Values) scalars() map[string]string {
	return map[string]string{
		"name":         v.Name,
		"owner":        v.Owner,
		"team":         v.Team,
		"description":  v.Description,
		"frontendPort": strconv.Itoa(v.FrontendPort),
		"backendPort":  strconv.Itoa(v.BackendPort),
	}
}

// Validate applies the same constraints the old scaffolder form enforced.
func (v Values) Validate() error {
	if !dnsLabel.MatchString(v.Name) {
		return fmt.Errorf("name %q must be a DNS-safe label (lowercase letters, digits, hyphens)", v.Name)
	}
	if !dnsLabel.MatchString(v.Team) {
		return fmt.Errorf("team %q must be a DNS-safe label", v.Team)
	}
	if strings.TrimSpace(v.Owner) == "" {
		return errors.New("owner must not be empty")
	}
	for _, port := range []int{v.FrontendPort, v.BackendPort} {
		if port < 1024 || port > 65535 {
			return fmt.Errorf("port %d must be between 1024 and 65535", port)
		}
	}
	if len(v.Environments) == 0 {
		return errors.New("at least one environment is required")
	}
	seen := map[string]bool{}
	for _, env := range v.Environments {
		if env != "dev" && env != "uat" {
			return fmt.Errorf("environment %q must be dev or uat", env)
		}
		if seen[env] {
			return fmt.Errorf("environment %q is listed twice", env)
		}
		seen[env] = true
	}
	return nil
}

// Render expands one template file's text.
func Render(text string, v Values) (string, error) {
	var out strings.Builder
	rest := collapseTagOnlyLines(text)
	for {
		start := strings.Index(rest, forOpen)
		if start < 0 {
			break
		}
		end := strings.Index(rest[start:], forClose)
		if end < 0 {
			return "", errors.New("for block is missing {% endfor %}")
		}
		end += start
		out.WriteString(rest[:start])
		body := rest[start+len(forOpen) : end]
		for i, env := range v.Environments {
			iteration, err := renderLoopBody(body, env, i == len(v.Environments)-1)
			if err != nil {
				return "", err
			}
			out.WriteString(iteration)
		}
		rest = rest[end+len(forClose):]
	}
	out.WriteString(rest)

	rendered := out.String()
	if strings.Contains(rendered, ifNotLast) || strings.Contains(rendered, ifClose) {
		return "", errors.New("{% if not loop.last %} is only valid inside a for block")
	}
	if envExpr.MatchString(rendered) {
		return "", errors.New("${{ environment }} is only valid inside a for block")
	}

	var missing error
	scalars := v.scalars()
	rendered = valueExpr.ReplaceAllStringFunc(rendered, func(match string) string {
		key := valueExpr.FindStringSubmatch(match)[1]
		value, ok := scalars[key]
		if !ok {
			missing = fmt.Errorf("unknown template value %q", key)
			return match
		}
		return value
	})
	if missing != nil {
		return "", missing
	}
	if tag := anyTag.FindString(rendered); tag != "" {
		return "", fmt.Errorf("unsupported template tag %s", tag)
	}
	if expr := anyExpr.FindString(rendered); expr != "" {
		return "", fmt.Errorf("unsupported template expression %s", expr)
	}
	return rendered, nil
}

func renderLoopBody(body, env string, last bool) (string, error) {
	var out strings.Builder
	rest := body
	for {
		start := strings.Index(rest, ifNotLast)
		if start < 0 {
			break
		}
		end := strings.Index(rest[start:], ifClose)
		if end < 0 {
			return "", errors.New("if block is missing {% endif %}")
		}
		end += start
		out.WriteString(rest[:start])
		if !last {
			out.WriteString(rest[start+len(ifNotLast) : end])
		}
		rest = rest[end+len(ifClose):]
	}
	out.WriteString(rest)
	return envExpr.ReplaceAllString(out.String(), env), nil
}

// collapseTagOnlyLines replaces each line that holds nothing but a tag with
// the bare tag, dropping its indentation and newline, so the tag's line
// vanishes from the output instead of leaving a blank or whitespace-only line.
func collapseTagOnlyLines(text string) string {
	lines := strings.SplitAfter(text, "\n")
	var out strings.Builder
	for _, line := range lines {
		if tagOnlyRow.MatchString(strings.TrimRight(line, "\n")) {
			out.WriteString(strings.TrimSpace(line))
			continue
		}
		out.WriteString(line)
	}
	return out.String()
}

// RenderTree renders every file under src into dst, keeping relative paths
// and file modes. dst must not exist yet.
func RenderTree(src, dst string, v Values) error {
	if _, err := os.Stat(dst); err == nil {
		return fmt.Errorf("output directory %s already exists", dst)
	}
	return filepath.WalkDir(src, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		target := filepath.Join(dst, rel)
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if entry.IsDir() {
			return os.MkdirAll(target, 0o755)
		}
		if !info.Mode().IsRegular() {
			return fmt.Errorf("%s: only regular files are supported", rel)
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		rendered, err := Render(string(data), v)
		if err != nil {
			return fmt.Errorf("%s: %w", rel, err)
		}
		return os.WriteFile(target, []byte(rendered), info.Mode().Perm())
	})
}

func main() {
	var (
		src          = flag.String("template", "", "template content directory (templates/platform-service/content)")
		dst          = flag.String("out", "", "output directory to create")
		name         = flag.String("name", "", "DNS-safe service name")
		owner        = flag.String("owner", "group:default/team-dolphin", "owning team reference")
		team         = flag.String("team", "dolphin", "DNS-safe team label")
		description  = flag.String("description", "A platform app created from the platform-service template.", "one-line description")
		frontendPort = flag.Int("frontend-port", 8080, "frontend container port")
		backendPort  = flag.Int("backend-port", 8080, "backend container port")
		environments = flag.String("environments", "dev", "comma-separated environments (dev, uat)")
	)
	flag.Parse()
	if *src == "" || *dst == "" {
		fmt.Fprintln(os.Stderr, "usage: render-service-template --template DIR --out DIR --name NAME [options]")
		flag.PrintDefaults()
		os.Exit(2)
	}

	envs := []string{}
	for _, env := range strings.Split(*environments, ",") {
		if env = strings.TrimSpace(env); env != "" {
			envs = append(envs, env)
		}
	}
	values := Values{
		Name:         *name,
		Owner:        *owner,
		Team:         *team,
		Description:  *description,
		FrontendPort: *frontendPort,
		BackendPort:  *backendPort,
		Environments: envs,
	}
	if err := values.Validate(); err != nil {
		fmt.Fprintf(os.Stderr, "render-service-template: %v\n", err)
		os.Exit(2)
	}
	if err := RenderTree(*src, *dst, values); err != nil {
		fmt.Fprintf(os.Stderr, "render-service-template: %v\n", err)
		os.Exit(1)
	}
}
