// Playlist page: view songs, rename, delete, remove songs.

const playlistId = new URLSearchParams(location.search).get("id");
const editForm = document.getElementById("edit-form");
let playlist;

async function loadPlaylist() {
  clearSqlPanel();
  playlist = await api("GET", `/playlists/${playlistId}`);
  document.title = `${playlist.playlist_name} · EXAAtunes`;

  const collaborators = playlist.collaborators.map(c => esc(c.username)).join(", ");
  const songCount = `${playlist.songs.length} ${playlist.songs.length === 1 ? "song" : "songs"}`;

  document.getElementById("playlist-header").innerHTML = `
    <div>
      <div class="label">Playlist</div>
      <h1>${esc(playlist.playlist_name)}</h1>
      ${playlist.description ? `<p class="description">${esc(playlist.description)}</p>` : ""}
      <p class="meta">
        By ${esc(playlist.owner)}${collaborators ? ` with ${collaborators}` : ""}
        · ${songCount}${playlist.songs.length ? `, ${formatLength(playlist.total_ms)}` : ""}
      </p>
      <div class="buttons">
        ${playlist.is_owner ? `
          <button type="button" id="edit-button">Edit details</button>
          <button type="button" id="delete-button" class="danger">Delete</button>` : ""}
      </div>
    </div>`;

  document.getElementById("songs").innerHTML = playlist.songs.length
    ? playlist.songs.map((song, i) => trackRow(song, {
        number: i + 1,
        meta: `<span class="added">${formatDate(song.added_at)}</span> · ${formatDuration(song.duration_ms)}`,
        actions: likeButton(song) + (playlist.can_edit
          ? `<button class="icon-button" data-action="remove" data-song-id="${song.song_id}"
                     title="Remove from playlist">${REMOVE_ICON}</button>`
          : ""),
      })).join("")
    : `<li class="empty">No songs yet.</li>`;
}

// ---------- Edit / delete ----------

document.getElementById("playlist-header").addEventListener("click", async event => {
  if (event.target.id === "edit-button") {
    editForm.elements.name.value = playlist.playlist_name;
    editForm.elements.description.value = playlist.description || "";
    editForm.hidden = false;
    editForm.elements.name.focus();
  }

  if (event.target.id === "delete-button") {
    if (!confirm(`Delete "${playlist.playlist_name}"? This can't be undone.`)) return;
    try {
      await api("DELETE", `/playlists/${playlistId}`);
      location.href = "/";
    } catch (error) {
      showMessage(error.message, true);
    }
  }
});

document.getElementById("cancel-edit").addEventListener("click", () => {
  editForm.hidden = true;
});

editForm.addEventListener("submit", async event => {
  event.preventDefault();
  try {
    await api("PATCH", `/playlists/${playlistId}`, {
      name: editForm.elements.name.value,
      description: editForm.elements.description.value,
    });
    editForm.hidden = true;
    await loadPlaylist();
    showMessage("Saved");
  } catch (error) {
    showMessage(error.message, true);
  }
});

// ---------- Remove a song ----------

document.getElementById("songs").addEventListener("click", async event => {
  const button = event.target.closest('[data-action="remove"]');
  if (!button) return;
  try {
    await api("DELETE", `/playlists/${playlistId}/songs/${button.dataset.songId}`);
    await loadPlaylist();
  } catch (error) {
    showMessage(error.message, true);
  }
});

if (playlistId) {
  loadPlaylist().catch(error => {
    document.getElementById("playlist-header").innerHTML = `<h1>${esc(error.message)}</h1>`;
  });
} else {
  location.href = "/";
}
