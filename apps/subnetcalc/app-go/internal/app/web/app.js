const paths = {
  health: "/api/v1/health",
  validate: "/api/v1/ipv4/validate",
  private: "/api/v1/ipv4/check-private",
  cloudflare: "/api/v1/ipv4/check-cloudflare",
  subnet: "/api/v1/ipv4/subnet-info",
  whoami: "/api/whoami",
};

document.addEventListener("DOMContentLoaded", () => {
  checkHealth();
  document.getElementById("lookup-form").addEventListener("submit", lookup);
  document.getElementById("identity-form").addEventListener("submit", whoami);
  document.querySelectorAll("[data-example]").forEach((button) => {
    button.addEventListener("click", () => {
      document.getElementById("ip-address").value = button.dataset.example;
    });
  });
});

async function checkHealth() {
  const status = document.getElementById("api-status");
  try {
    const data = await getJSON(paths.health);
    status.textContent = `API Status: ${data.status} | Backend: ${data.service} | Version: ${data.version}`;
  } catch (error) {
    status.textContent = `API unavailable: ${error.message}`;
    status.classList.add("error");
  }
}

async function lookup(event) {
  event.preventDefault();
  const address = document.getElementById("ip-address").value.trim();
  const mode = document.getElementById("cloud-mode").value;
  const results = document.getElementById("results");
  const content = document.getElementById("results-content");
  results.hidden = false;
  content.textContent = "Loading...";

  try {
    const started = performance.now();
    const validation = await timedPostJSON(paths.validate, { address });
    const privateCheck = validation.data.is_ipv4 ? await timedPostJSON(paths.private, { address }) : null;
    const cloudflare = await timedPostJSON(paths.cloudflare, { address });
    const subnet = validation.data.type === "network" && validation.data.is_ipv4
      ? await timedPostJSON(paths.subnet, { network: address, mode })
      : null;
    const totalMs = Math.round(performance.now() - started);
    content.innerHTML = renderResults(validation, privateCheck, cloudflare, subnet);
    content.insertAdjacentHTML("beforeend", renderPerformance(totalMs));
  } catch (error) {
    content.innerHTML = `<p class="error">Error: ${escapeHTML(error.message)}</p>`;
  }
}

async function whoami(event) {
  event.preventDefault();
  const token = document.getElementById("token-input").value.trim();
  const authState = document.getElementById("auth-state");
  try {
    const user = await getJSON(paths.whoami, token ? { Authorization: `Bearer ${token}` } : {});
    authState.textContent = `Signed in as ${user.preferred_username || user.email || user.sub}`;
  } catch (error) {
    authState.textContent = `Not signed in: ${error.message}`;
  }
}

async function getJSON(path, headers = {}) {
  const response = await fetch(path, { headers });
  return parseJSONResponse(response);
}

async function postJSON(path, body) {
  const response = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return parseJSONResponse(response);
}

async function timedPostJSON(path, body) {
  const started = performance.now();
  const requestUtc = new Date().toISOString();
  const data = await postJSON(path, body);
  const responseUtc = new Date().toISOString();
  return {
    data,
    timing: {
      durationMs: Math.round(performance.now() - started),
      requestUtc,
      responseUtc,
    },
  };
}

async function parseJSONResponse(response) {
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.detail || `HTTP ${response.status}`);
  }
  return data;
}

function renderResults(validation, privateCheck, cloudflare, subnet) {
  const validationRows = [
    ["Valid", validation.data.valid ? "Yes" : "No"],
    ["Address", validation.data.address],
    ["Type", validation.data.type === "network" ? "Network (CIDR)" : "Host Address"],
    ["IP Version", validation.data.is_ipv4 ? "IPv4" : "IPv6"],
  ];

  const sections = [renderArticle("Validation", validationRows, validation.timing)];

  if (privateCheck) {
    sections.push(renderArticle("Private Address Check", [
      ["RFC1918", privateCheck.data.is_rfc1918 ? `Yes (${privateCheck.data.matched_rfc1918_range})` : "No"],
      ["RFC6598 Shared", privateCheck.data.is_rfc6598 ? `Yes (${privateCheck.data.matched_rfc6598_range})` : "No"],
    ], privateCheck.timing));
  }

  sections.push(renderArticle("Cloudflare Check", [
    ["Cloudflare", cloudflare.data.is_cloudflare ? `Yes (${(cloudflare.data.matched_ranges || []).join(", ")})` : "No"],
  ], cloudflare.timing));

  if (subnet) {
    const subnetRows = [
      ["Mode", subnet.data.mode],
      ["Network Address", subnet.data.network_address],
      ["Netmask", subnet.data.netmask],
      ["Wildcard Mask", subnet.data.wildcard_mask],
      ["Prefix Length", `/${subnet.data.prefix_length}`],
      ["Total Addresses", subnet.data.total_addresses.toLocaleString()],
      ["Usable Addresses", subnet.data.usable_addresses.toLocaleString()],
      ["First Usable IP", subnet.data.first_usable_ip],
      ["Last Usable IP", subnet.data.last_usable_ip],
    ];
    if (subnet.data.broadcast_address) subnetRows.splice(2, 0, ["Broadcast Address", subnet.data.broadcast_address]);
    if (subnet.data.note) subnetRows.push(["Note", subnet.data.note]);
    sections.push(renderArticle("Subnet Information", subnetRows, subnet.timing));
  }

  return sections.join("");
}

function renderArticle(title, rows, timing) {
  return `<article><h3>${escapeHTML(title)}</h3>${renderTable(rows)}${renderTiming(timing)}</article>`;
}

function renderTable(rows) {
  return `<table><tbody>${rows.map(([key, value]) => `<tr><th>${escapeHTML(key)}</th><td>${escapeHTML(String(value || ""))}</td></tr>`).join("")}</tbody></table>`;
}

function renderTiming(timing) {
  return `<details><summary>API Call Timing</summary>${renderTable([
    ["Duration", `${timing.durationMs}ms`],
    ["Request (UTC)", timing.requestUtc],
    ["Response (UTC)", timing.responseUtc],
  ])}</details>`;
}

function renderPerformance(totalMs) {
  return `<article><h3>Performance Timing</h3>${renderTable([
    ["Total Response Time", `${totalMs}ms (${(totalMs / 1000).toFixed(3)}s)`],
  ])}</article>`;
}

function escapeHTML(value) {
  return value.replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[char]);
}
