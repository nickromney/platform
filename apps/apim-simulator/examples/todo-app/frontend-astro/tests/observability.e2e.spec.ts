import { expect, test } from "@playwright/test";

const grafanaBaseUrl = process.env.GRAFANA_BASE_URL || "https://lgtm.apim.127.0.0.1.sslip.io:8443";

test("lets a user jump from the todo flow into the Grafana OTEL dashboard", async ({ context, page }) => {
  const title = `Observability todo ${Date.now()}`;

  await page.goto("/");

  await expect(page.getByTestId("gateway-status")).toContainText("Connected via APIM");
  await page.getByLabel("Add a new task").fill(title);
  await page.getByRole("button", { name: "Create" }).click();

  const todoItem = page.getByRole("button", { name: new RegExp(title) });
  await expect(todoItem).toContainText("Open");
  await todoItem.click();
  await expect(todoItem).toContainText("Done");

  const [dashboard] = await Promise.all([
    context.waitForEvent("page"),
    page.getByTestId("observability-dashboard-link").click(),
  ]);

  await dashboard.waitForLoadState("domcontentloaded");
  await expect(dashboard).toHaveURL(`${grafanaBaseUrl}/d/apim-simulator-overview/apim-simulator-overview`);
  await expect(dashboard).not.toHaveURL(/\/login/);
  await expect(dashboard.getByText("APIM Simulator Overview")).toBeVisible();
  await expect(dashboard.getByText("Gateway Request Rate")).toBeVisible();
  const tracePanel = dashboard.getByText("Trace Span Throughput");
  await tracePanel.scrollIntoViewIfNeeded();
  await expect(tracePanel).toBeVisible();

  const logsPanel = dashboard.getByText("Recent OTEL Logs");
  await logsPanel.scrollIntoViewIfNeeded();
  await expect(logsPanel).toBeVisible();
});
