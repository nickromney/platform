import { test, expect } from '@playwright/test';

const CLOUDS = [
  { name: 'Cloud1', url: 'http://localhost:58081', ip: '10.1.0.20' },
  { name: 'Cloud2', url: 'http://localhost:8082', ip: '10.2.0.20' },
  { name: 'Cloud3', url: 'http://localhost:8083', ip: '10.3.0.20' },
];

for (const cloud of CLOUDS) {
  test(`${cloud.name} - main page loads`, async ({ page }) => {
    await page.goto(cloud.url);
    
    // Check the cloud name is displayed
    await expect(page.locator('h1')).toContainText(`SD-WAN API - ${cloud.name}`);
    
    // Check the cloud IP is shown
    await expect(page.locator('.value').first()).toContainText(cloud.ip);
  });
}

test('Cloud1 can call Cloud2 via proxy', async ({ page }) => {
  const response = await page.request.get('http://localhost:58081/proxy/cloud2');
  const json = await response.json();
  
  expect(json.this_system).toBe('Cloud1');
  expect(json.called_system).toBe('cloud2');
  expect(json.status).toBe(200);
});

test('Cloud1 can call Cloud3 via proxy', async ({ page }) => {
  const response = await page.request.get('http://localhost:58081/proxy/cloud3');
  const json = await response.json();
  
  expect(json.this_system).toBe('Cloud1');
  expect(json.called_system).toBe('cloud3');
  expect(json.status).toBe(200);
});

test('Cloud2 can call Cloud1 via proxy', async ({ page }) => {
  const response = await page.request.get('http://localhost:8082/proxy/cloud1');
  const json = await response.json();
  
  expect(json.this_system).toBe('Cloud2');
  expect(json.called_system).toBe('cloud1');
  expect(json.status).toBe(200);
});

test('Cross-cloud calls show client IP', async ({ page }) => {
  const response = await page.request.get('http://localhost:58081/proxy/cloud2');
  const json = await response.json();
  
  // Should have client_ip field
  expect(json.client_ip).toBeTruthy();
  expect(json.this_system).toBe('Cloud1');
});

test('/info endpoint returns cloud details', async ({ page }) => {
  const response = await page.request.get('http://localhost:58081/info');
  const json = await response.json();
  
  expect(json.system).toBe('Cloud1');
  expect(json.ip).toBe('10.1.0.20');
  expect(json.client_ip).toBeTruthy();
});

test('DNS query returns resolved IP', async ({ page }) => {
  const response = await page.request.get('http://localhost:58081/dns-raw?domain=app.cloud1.test');
  const json = await response.json();
  
  expect(json.query).toBe('app.cloud1.test');
  expect(json.resolver).toContain('10.1.0.10');
});
