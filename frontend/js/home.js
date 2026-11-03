// Home page: recently played, top artists, playlists.

async function loadHome() {
  clearSqlPanel();
  const data = await api("GET", "/home");

  const hours = Math.round(data.stats.minutes / 60);
  document.getElementById("stats").textContent =
    `${data.stats.plays.toLocaleString()} plays and ${hours} hours of listening in the last 30 days`;

  document.getElementById("recent").innerHTML = data.recent.length
    ? data.recent.map(song => trackRow(song, { meta: formatDateTime(song.played_at) })).join("")
    : `<li class="empty">Nothing played yet.</li>`;

  document.getElementById("top-artists").innerHTML = data.top_artists.length
    ? data.top_artists.map((artist, i) => `
        <li>
          <span class="rank">${i + 1}</span>
          <span class="name">${esc(artist.artist_name)}</span>
          <span class="count">${artist.plays.toLocaleString()} plays</span>
        </li>`).join("")
    : `<li class="empty">No listening in the last 30 days.</li>`;

  renderPlaylists(data.playlists);
}

function renderPlaylists(playlists) {
  document.getElementById("playlists").innerHTML = playlists.length
    ? playlists.map(p => `
        <li>
          <a class="name" href="/playlist.html?id=${p.playlist_id}">${esc(p.playlist_name)}</a>
          <span class="count">${p.is_owner ? "" : `by ${esc(p.owner)} · `}${p.song_count} songs</span>
        </li>`).join("")
    : `<li class="empty">No playlists yet.</li>`;
}

// ---------- New playlist ----------

const form = document.getElementById("new-playlist-form");

document.getElementById("new-playlist-button").addEventListener("click", () => {
  form.hidden = false;
  form.elements.name.focus();
});

document.getElementById("cancel-new-playlist").addEventListener("click", () => {
  form.reset();
  form.hidden = true;
});

form.addEventListener("submit", async event => {
  event.preventDefault();
  try {
    const created = await api("POST", "/playlists", {
      name: form.elements.name.value,
      description: form.elements.description.value,
    });
    location.href = `/playlist.html?id=${created.playlist_id}`;
  } catch (error) {
    showMessage(error.message, true);
  }
});

loadHome().catch(error => showMessage(error.message, true));
