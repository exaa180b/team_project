// Shared code for every page: API calls, the "Viewing as" picker, the SQL panel,
// track rows and formatting helpers.

// ---------- Current user ----------

function currentUserId() {
  return Number(localStorage.getItem("userId")) || 1;
}

async function setupUserPicker() {
  const select = document.getElementById("user-select");
  const users = await api("GET", "/users", null, { log: false });
  select.innerHTML = users
    .map(u => `<option value="${u.user_id}">${esc(u.username)}</option>`)
    .join("");
  select.value = currentUserId();
  select.addEventListener("change", () => {
    localStorage.setItem("userId", select.value);
    location.reload();
  });
}

// ---------- API ----------

// Calls the backend. Returns the response's "data", and adds its SQL to the SQL panel.
async function api(method, path, body = null, { log = true } = {}) {
  const response = await fetch("/api" + path, {
    method,
    headers: { "Content-Type": "application/json", "X-User-Id": currentUserId() },
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await response.json().catch(() => ({}));
  if (log && json.queries) logQueries(json.queries);
  if (!response.ok) {
    const detail = typeof json.detail === "string" ? json.detail : "Something went wrong";
    throw new Error(detail);
  }
  return json.data;
}

// ---------- SQL panel ----------

let sqlLog = [];

function clearSqlPanel() {
  sqlLog = [];
  renderSqlPanel();
}

function logQueries(queries) {
  sqlLog.push(...queries);
  renderSqlPanel();
}

function renderSqlPanel() {
  const panel = document.getElementById("sql-panel");
  if (!panel) return;
  const totalMs = sqlLog.reduce((sum, q) => sum + q.ms, 0);
  const plural = sqlLog.length === 1 ? "query" : "queries";
  panel.querySelector(".sql-summary").textContent =
    `· ${sqlLog.length} ${plural} · ${totalMs.toFixed(1)} ms`;
  panel.querySelector(".sql-list").innerHTML = sqlLog.map(q => `
    <div class="sql-entry">
      <div class="sql-meta">${q.ms.toFixed(1)} ms${Object.keys(q.params).length ? " · params " + esc(JSON.stringify(q.params)) : ""}</div>
      <pre>${esc(q.sql)}</pre>
    </div>`).join("");
}

// ---------- Rendering helpers ----------

// Escape text before putting it into HTML (song titles can contain < & etc.).
function esc(text) {
  return String(text ?? "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

const HEART_ICON = `<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 21s-7.5-4.6-9.6-9.2C.9 8.4 3 4.5 6.7 4.5c2.1 0 3.6 1.1 4.4 2.5h1.8c.8-1.4 2.3-2.5 4.4-2.5 3.7 0 5.8 3.9 4.3 7.3C19.5 16.4 12 21 12 21z"/></svg>`;
const HEART_OUTLINE_ICON = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M12 20s-7-4.3-9-8.6C1.6 8.3 3.6 5 6.8 5c2 0 3.6 1.1 4.4 2.6h1.6C13.6 6.1 15.2 5 17.2 5c3.2 0 5.2 3.3 3.8 6.4C19 15.7 12 20 12 20z"/></svg>`;
const REMOVE_ICON = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>`;

function likeButton(song) {
  return `<button class="icon-button like" data-action="like" data-song-id="${song.song_id}"
            aria-pressed="${song.liked}" title="${song.liked ? "Unlike" : "Like"}">
            ${song.liked ? HEART_ICON : HEART_OUTLINE_ICON}</button>`;
}

// One row of a track list. `meta` is the small text on the right (a time or duration),
// `actions` is extra HTML for buttons, `number` shows a position number.
function trackRow(song, { meta = "", actions = "", number = null } = {}) {
  return `
    <li class="track${number !== null ? " numbered" : ""}">
      ${number !== null ? `<span class="num">${number}</span>` : ""}
      <div class="info">
        <div class="title">${esc(song.song_title)}</div>
        <div class="artists">${esc(song.artists)}</div>
      </div>
      <div class="album">${esc(song.album_title)}</div>
      <span class="meta">${meta}</span>
      <span class="actions">${actions}</span>
    </li>`;
}

// Like / unlike buttons work the same on every page.
document.addEventListener("click", async event => {
  const button = event.target.closest('[data-action="like"]');
  if (!button) return;
  const liked = button.getAttribute("aria-pressed") === "true";
  button.disabled = true;
  try {
    await api(liked ? "DELETE" : "POST", `/songs/${button.dataset.songId}/like`);
    button.setAttribute("aria-pressed", String(!liked));
    button.title = liked ? "Like" : "Unlike";
    button.innerHTML = liked ? HEART_OUTLINE_ICON : HEART_ICON;
  } catch (error) {
    showMessage(error.message, true);
  } finally {
    button.disabled = false;
  }
});

// ---------- Formatting ----------

function formatDuration(ms) {
  const totalSeconds = Math.round(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = String(totalSeconds % 60).padStart(2, "0");
  return `${minutes}:${seconds}`;
}

function formatLength(ms) {
  const minutes = Math.round(ms / 60000);
  if (minutes < 60) return `${minutes} min`;
  return `${Math.floor(minutes / 60)} hr ${minutes % 60} min`;
}

function formatDateTime(iso) {
  return new Date(iso).toLocaleString(undefined, {
    month: "short", day: "numeric", hour: "numeric", minute: "2-digit",
  });
}

function formatDate(iso) {
  return new Date(iso).toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" });
}

// ---------- Messages ----------

let messageTimer;

function showMessage(text, isError = false) {
  const box = document.getElementById("message");
  box.textContent = text;
  box.classList.toggle("error", isError);
  box.hidden = false;
  clearTimeout(messageTimer);
  messageTimer = setTimeout(() => { box.hidden = true; }, 3000);
}

setupUserPicker().catch(error => showMessage(error.message, true));
