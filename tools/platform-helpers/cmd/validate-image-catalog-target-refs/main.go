package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
)

var mapLineRE = regexp.MustCompile(`^\s*(?:"([^"]+)"|([A-Za-z0-9_-]+))\s*=\s*"([^"]*)"\s*$`)

func main() {
	catalogPath := flag.String("catalog", "", "workflow image catalog JSON path")
	target := flag.String("target", "", "target variant")
	tfvarsPath := flag.String("tfvars", "", "tfvars path")
	printExpected := flag.Bool("print-expected", false, "print catalog-rendered external image ref tfvars maps")
	allowSourceTags := flag.Bool("allow-source-tags", false, "allow generated src-<digest> tags for fingerprinted images")
	flag.Parse()

	if *catalogPath == "" || *target == "" {
		fmt.Fprintln(os.Stderr, "--catalog and --target are required")
		os.Exit(2)
	}

	catalog := readJSONMap(*catalogPath)
	checks := []struct {
		category  string
		tfvarsKey string
	}{
		{"platform", "external_platform_image_refs"},
		{"workload", "external_workload_image_refs"},
	}

	if *printExpected {
		rendered := []string{}
		for _, check := range checks {
			expected, _ := catalogRefs(catalog, *target, check.category)
			rendered = append(rendered, renderHCLMap(check.tfvarsKey, expected))
		}
		fmt.Println(strings.Join(rendered, "\n\n"))
		return
	}

	if *tfvarsPath == "" {
		fmt.Fprintln(os.Stderr, "--tfvars is required unless --print-expected is used")
		os.Exit(2)
	}

	failures := []string{}
	for _, check := range checks {
		expected, sourceTagKeys := catalogRefs(catalog, *target, check.category)
		actual := hclStringMap(*tfvarsPath, check.tfvarsKey)
		failures = append(failures, diffLines(expected, actual, check.tfvarsKey, sourceTagKeys, *allowSourceTags)...)
	}
	if len(failures) > 0 {
		fmt.Fprintln(os.Stderr, strings.Join(failures, "\n"))
		os.Exit(1)
	}
	fmt.Printf("validated %s external image refs against image catalog\n", *target)
}

func readJSONMap(path string) map[string]any {
	data, err := os.ReadFile(path)
	if err != nil {
		exitf("read catalog: %v", err)
	}
	var value map[string]any
	if err := json.Unmarshal(data, &value); err != nil {
		exitf("parse catalog: %v", err)
	}
	return value
}

func hclStringMap(tfvarsPath, name string) map[string]string {
	data, err := os.ReadFile(tfvarsPath)
	if err != nil {
		exitf("read tfvars: %v", err)
	}
	values := map[string]string{}
	inMap := false
	for _, line := range strings.Split(string(data), "\n") {
		stripped := strings.TrimSpace(line)
		if !inMap {
			if stripped == name+" = {" {
				inMap = true
			}
			continue
		}
		if stripped == "}" {
			return values
		}
		if stripped == "" || strings.HasPrefix(stripped, "#") {
			continue
		}
		matches := mapLineRE.FindStringSubmatch(line)
		if len(matches) != 4 {
			exitf("%s: unsupported %s line: %s", tfvarsPath, name, line)
		}
		key := matches[1]
		if key == "" {
			key = matches[2]
		}
		values[key] = matches[3]
	}
	exitf("%s: missing %s map", tfvarsPath, name)
	return nil
}

func catalogRefs(catalog map[string]any, target, category string) (map[string]string, map[string]bool) {
	registryHosts, ok := catalog["variant_registry_hosts"].(map[string]any)
	if !ok || registryHosts[target] == nil {
		exitf("image catalog does not declare registry host for target %q", target)
	}
	registryHost, ok := registryHosts[target].(string)
	if !ok || registryHost == "" {
		exitf("image catalog registry host for target %q must be a non-empty string", target)
	}
	namespace, ok := catalog["namespace"].(string)
	if !ok || namespace == "" {
		exitf("image catalog namespace must be a non-empty string")
	}
	rawImages, ok := catalog[category+"_images"].([]any)
	if !ok {
		exitf("image catalog missing %s_images", category)
	}
	refs := map[string]string{}
	sourceTagKeys := map[string]bool{}
	for _, rawImage := range rawImages {
		image, ok := rawImage.(map[string]any)
		if !ok {
			exitf("%s_images contains a non-object entry", category)
		}
		if value, ok := image["external_ref"].(bool); ok && !value {
			continue
		}
		hclKey := requiredString(image, "hcl_key", category)
		imageName := requiredString(image, "image_name", category)
		tag := requiredString(image, "default_tag", category)
		refs[hclKey] = fmt.Sprintf("%s/%s/%s:%s", registryHost, namespace, imageName, tag)
		if _, ok := image["fingerprint_sources"]; ok {
			sourceTagKeys[hclKey] = true
		}
	}
	return refs, sourceTagKeys
}

func requiredString(image map[string]any, key, category string) string {
	value, ok := image[key].(string)
	if !ok || value == "" {
		id, _ := image["id"].(string)
		if id == "" {
			id = "<missing id>"
		}
		exitf("%s_images.%s.%s must be a non-empty string", category, id, key)
	}
	return value
}

func renderHCLMap(name string, values map[string]string) string {
	keys := sortedKeys(values)
	width := 0
	for _, key := range keys {
		if l := len(renderHCLKey(key)); l > width {
			width = l
		}
	}
	lines := []string{name + " = {"}
	for _, key := range keys {
		lines = append(lines, fmt.Sprintf("  %-*s = %s", width, renderHCLKey(key), renderHCLString(values[key])))
	}
	lines = append(lines, "}")
	return strings.Join(lines, "\n")
}

func renderHCLKey(key string) string {
	if regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`).MatchString(key) {
		return key
	}
	return renderHCLString(key)
}

func renderHCLString(value string) string {
	return `"` + strings.ReplaceAll(strings.ReplaceAll(value, `\`, `\\`), `"`, `\"`) + `"`
}

func diffLines(expected, actual map[string]string, label string, sourceTagKeys map[string]bool, allowSourceTags bool) []string {
	lines := []string{}
	for _, key := range sortedSetDifference(expected, actual) {
		lines = append(lines, fmt.Sprintf("%s: missing %s = %s", label, key, expected[key]))
	}
	for _, key := range sortedSetDifference(actual, expected) {
		lines = append(lines, fmt.Sprintf("%s: unexpected %s = %s", label, key, actual[key]))
	}
	for _, key := range sortedKeys(expected) {
		actualValue, ok := actual[key]
		if !ok {
			continue
		}
		if !refsMatch(expected[key], actualValue, allowSourceTags && sourceTagKeys[key]) {
			lines = append(lines, fmt.Sprintf("%s: %s expected %s, got %s", label, key, expected[key], actualValue))
		}
	}
	return lines
}

func refsMatch(expected, actual string, allowSourceTag bool) bool {
	if actual == expected {
		return true
	}
	if !allowSourceTag {
		return false
	}
	expectedRepo, _, okExpected := splitImageTag(expected)
	actualRepo, actualTag, okActual := splitImageTag(actual)
	return okExpected && okActual && expectedRepo == actualRepo && regexp.MustCompile(`^src-[0-9a-f]{20}$`).MatchString(actualTag)
}

func splitImageTag(ref string) (string, string, bool) {
	index := strings.LastIndex(ref, ":")
	if index < 0 {
		return "", "", false
	}
	return ref[:index], ref[index+1:], true
}

func sortedSetDifference(left, right map[string]string) []string {
	keys := []string{}
	for key := range left {
		if _, exists := right[key]; !exists {
			keys = append(keys, key)
		}
	}
	sort.Strings(keys)
	return keys
}

func sortedKeys(values map[string]string) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func exitf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
