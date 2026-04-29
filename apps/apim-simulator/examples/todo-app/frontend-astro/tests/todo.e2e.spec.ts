import { expect, test } from "@playwright/test";

const apiBaseUrl = process.env.API_BASE_URL || "http://localhost:8000";

test("creates a todo through APIM, toggles it complete, and survives reload", async ({ page }) => {
  const title = `Gateway todo ${Date.now()}`;

  await page.goto("/");

  await expect(page.getByTestId("gateway-status")).toContainText("Connected via APIM");
  await expect(page.getByTestId("policy-indicator")).toContainText("applied");
  await expect(page.getByTestId("network-path")).toContainText("APIM simulator");
  await expect(page.getByTestId("network-path")).toContainText("Configured upstream route /api -> /api");
  await expect(page.getByTestId("api-call-log")).toContainText("GET");
  await expect(page.getByTestId("api-call-log")).toContainText(`${apiBaseUrl}/api/health`);
  await expect(page.getByTestId("api-call-log")).toContainText(`${apiBaseUrl}/api/todos`);

  await page.getByLabel("Add a new task").fill(title);
  await page.getByRole("button", { name: "Create" }).click();
  await expect(page.getByTestId("api-call-log")).toContainText("POST");
  await expect(page.getByTestId("api-call-log")).toContainText(title);

  const todoItem = page.getByRole("button", { name: new RegExp(title) });
  await expect(todoItem).toContainText(title);
  await expect(todoItem).toContainText("Open");

  await todoItem.click();
  await expect(todoItem).toContainText("Done");
  await expect(page.getByTestId("api-call-log")).toContainText("PATCH");

  await page.reload();

  const persistedTodo = page.getByRole("button", { name: new RegExp(title) });
  await expect(persistedTodo).toContainText("Done");
  await expect(page.getByTestId("error-banner")).toBeHidden();
});

test("renders a visible error when the APIM subscription key is invalid", async ({ page }) => {
  await page.route("**/runtime-config.js", async (route) => {
    await route.fulfill({
      contentType: "application/javascript",
      body: `window.RUNTIME_CONFIG = {
        API_BASE_URL: "${apiBaseUrl}",
        APIM_SUBSCRIPTION_KEY: "bad-subscription-key"
      };`,
    });
  });

  await page.goto("/");

  await expect(page.getByTestId("gateway-status")).toContainText("Gateway error");
  await expect(page.getByTestId("error-banner")).toContainText("Invalid subscription key");
  await expect(page.getByTestId("api-call-log")).toContainText("401");
  await expect(page.getByTestId("api-call-log")).toContainText(`${apiBaseUrl}/api/health`);
});
