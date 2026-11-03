// SQL Console page: type a query, run it, see the results as a table.

const form = document.getElementById("sql-form");
const input = document.getElementById("sql-input");
const resultsBox = document.getElementById("sql-results");

// Keep the last query, so it's still there after a refresh.
input.value = localStorage.getItem("sqlConsoleQuery") || "";

async function runQuery() {
  const sql = input.value.trim();
  if (!sql) return;
  localStorage.setItem("sqlConsoleQuery", input.value);
  resultsBox.innerHTML = `<p class="muted">Running…</p>`;
  try {
    const data = await api("POST", "/sql", { sql, allow_changes: form.elements.allow_changes.checked });
    resultsBox.innerHTML = `<p class="muted">Finished in ${data.ms.toFixed(1)} ms</p>`
      + data.results.map(resultTable).join("");
  } catch (error) {
    resultsBox.innerHTML = `<pre class="sql-error">${esc(error.message)}</pre>`;
  }
}

function resultTable(result) {
  if (!result.columns) {
    // INSERT, UPDATE, CREATE, ... have no rows, just a status like "UPDATE 3".
    return `<p class="sql-status">${esc(result.status)}</p>`;
  }
  const count = result.truncated
    ? "First 500 rows"
    : `${result.rows.length} ${result.rows.length === 1 ? "row" : "rows"}`;
  const head = result.columns.map(c => `<th>${esc(c)}</th>`).join("");
  const body = result.rows.map(row =>
    `<tr>${row.map(value => `<td>${value === null ? `<span class="muted">NULL</span>` : esc(value)}</td>`).join("")}</tr>`
  ).join("");
  return `
    <p class="sql-status">${count}</p>
    <div class="table-wrap">
      <table class="result-table"><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>
    </div>`;
}

form.addEventListener("submit", event => {
  event.preventDefault();
  runQuery();
});

input.addEventListener("keydown", event => {
  if (event.key === "Enter" && (event.ctrlKey || event.metaKey)) {
    event.preventDefault();
    runQuery();
  }
});
