const statusEl = document.getElementById("status");
const commentsEl = document.getElementById("comments");
const textarea = document.getElementById("comment-text");

document.addEventListener("DOMContentLoaded", () => {
  document.getElementById("comment-form").addEventListener("submit", submitComment);
  document.querySelector('[data-sample="positive"]').addEventListener("click", () => {
    textarea.value = "I absolutely love this. Great work and fantastic experience.";
  });
  document.querySelector('[data-sample="mixed"]').addEventListener("click", () => {
    textarea.value = "Some parts are fine, but overall I am disappointed and frustrated.";
  });
  loadComments();
});

async function loadComments() {
  const data = await fetchJSON("/api/v1/comments?limit=25");
  renderComments(data.items || []);
  statusEl.textContent = "Ready.";
}

async function submitComment(event) {
  event.preventDefault();
  const text = textarea.value.trim();
  if (!text) {
    statusEl.textContent = "Text is required.";
    return;
  }
  const result = await fetchJSON("/api/v1/comments", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text }),
  });
  statusEl.textContent = `Saved. ${result.label} | Latency: ${result.latency_ms}ms`;
  textarea.value = "";
  await loadComments();
}

async function fetchJSON(url, options) {
  const response = await fetch(url, options);
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error || `HTTP ${response.status}`);
  }
  return payload;
}

function renderComments(items) {
  if (items.length === 0) {
    commentsEl.innerHTML = "<p>No comments yet.</p>";
    return;
  }
  commentsEl.innerHTML = items.map((item) => `
    <article class="comment">
      <span class="label">${escapeHTML(item.label)}</span>
      <span class="meta">Confidence: ${Number(item.confidence).toFixed(2)} | Latency: ${item.latency_ms}ms</span>
      <p>${escapeHTML(item.text)}</p>
    </article>
  `).join("");
}

function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[char]);
}
