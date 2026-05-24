package catalog

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCatalog(t *testing.T) {
	content := `{
  "applications": [
    {
      "name": "test-app",
      "deployment": {
        "controller": "argocd",
        "image": "base-image"
      },
      "environments": [
        {
          "name": "dev",
          "route": "https://dev.example.com"
        },
        {
          "name": "prod",
          "deployment": {
            "image": "prod-image"
          }
        }
      ],
      "secrets": [
        { "name": "db-password", "binding": "db" }
      ]
    }
  ]
}`
	tmpDir := t.TempDir()
	path := filepath.Join(tmpDir, "catalog.json")
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		t.Fatal(err)
	}

	c, err := Load(path)
	if err != nil {
		t.Fatal(err)
	}

	if len(c.Applications) != 1 {
		t.Fatalf("expected 1 app, got %d", len(c.Applications))
	}

	app, ok := c.GetApp("test-app")
	if !ok || app.Name != "test-app" {
		t.Fatal("could not find test-app")
	}

	deployments := c.ListDeployments()
	if len(deployments) != 2 {
		t.Fatalf("expected 2 deployments, got %d", len(deployments))
	}

	if deployments[0].Image != "base-image" {
		t.Errorf("dev image: expected base-image, got %s", deployments[0].Image)
	}
	if deployments[1].Image != "prod-image" {
		t.Errorf("prod image: expected prod-image, got %s", deployments[1].Image)
	}

	secrets := c.ListSecrets()
	if len(secrets) != 1 || secrets[0].Name != "db-password" || secrets[0].App != "test-app" {
		t.Errorf("unexpected secrets: %+v", secrets)
	}
}
