"""Turn the raw Spotify CSV into one clean CSV per table, ready for \\copy.

Reads  data/source/spotify_tracks_pop70.csv  (Spotify tracks with popularity >= 70)
       data/data_inserts.sql                 (the hand-entered catalog, so we don't add it twice)
Writes data/spotify/genres.csv, artists.csv, albums.csv, songs.csv, song_artist.csv, song_genre.csv

ids continue after the hand-entered ones in data_inserts.sql. Only needs to run again
if the source CSV changes; the output files are committed.

Usage (from the repo root):
    python data/clean_spotify_data.py
"""
import csv
import re
from collections import Counter
from pathlib import Path

OUT = Path("data/spotify")

# Spotify tags songs with ~100 small genres. Each one maps to one of our broad genres.
GENRE_MAP = {
    "Pop": ["pop", "dance", "power-pop", "synth-pop", "mandopop", "cantopop"],
    "Rock": ["rock", "alt-rock", "alternative", "hard-rock", "grunge", "psych-rock", "garage",
             "rock-n-roll", "rockabilly", "guitar", "j-rock"],
    "Indie": ["indie", "indie-pop"],
    "Hip-Hop": ["hip-hop"],
    "Electronic": ["electro", "edm", "house", "progressive-house", "deep-house", "chicago-house",
                   "techno", "trance", "dubstep", "electronic", "idm", "hardstyle", "club", "trip-hop"],
    "Metal": ["metal", "metalcore", "hardcore", "death-metal", "industrial"],
    "Punk": ["punk", "punk-rock", "emo", "ska"],
    "Latin": ["latin", "latino", "reggaeton", "salsa", "pagode", "brazil"],
    "Reggae": ["reggae", "dancehall", "dub"],
    "R&B": ["r-n-b"],
    "Soul": ["soul", "funk", "groove"],
    "Jazz": ["jazz"],
    "Country": ["country"],
    "Folk": ["folk", "acoustic", "songwriter", "singer-songwriter"],
    "Blues": ["blues"],
    "Disco": ["disco"],
    "K-Pop": ["k-pop"],
    "J-Pop": ["j-pop", "j-dance"],
    "Soundtrack": ["pop-film", "show-tunes", "disney", "anime"],
    "Classical": ["classical"],
    "World": ["afrobeat", "world-music", "indian", "turkish", "malay"],
}
# Mood and country tags. Only used when a song has no real genre tag.
BACKUP_MAP = {
    "Pop": ["sad", "chill", "party", "piano", "comedy", "children", "german", "swedish", "french"],
    "Rock": ["british"],
    "Electronic": ["ambient"],
    "Latin": ["spanish"],
    "Classical": ["sleep", "new-age"],
}
TAG_TO_GENRE = {tag: genre for genre, tags in GENRE_MAP.items() for tag in tags}
BACKUP_TAG_TO_GENRE = {tag: genre for genre, tags in BACKUP_MAP.items() for tag in tags}


def pick_genres(tags):
    """Up to 2 broad genres: the ones most of the song's tags point to."""
    # Spotify tags a lot of reggaeton as "reggae", so ignore it on Latin songs.
    if "reggae" in tags and {"latin", "latino", "reggaeton"} & set(tags):
        tags = [t for t in tags if t != "reggae"]
    for tag in tags:
        if tag not in TAG_TO_GENRE and tag not in BACKUP_TAG_TO_GENRE:
            raise ValueError(f"No genre for Spotify tag {tag!r}; add it to GENRE_MAP")
    counts = Counter(TAG_TO_GENRE[t] for t in tags if t in TAG_TO_GENRE)
    if not counts:
        counts = Counter(BACKUP_TAG_TO_GENRE[t] for t in tags)
    ranked = sorted(counts, key=lambda genre: (-counts[genre], genre))
    return ranked[:2]


def read_hand_entered_catalog():
    """Genres, artists, albums and Spotify ids already in data_inserts.sql."""
    sql = Path("data/data_inserts.sql").read_text(encoding="utf-8")

    def section(table):
        return sql.split(f"INSERT INTO {table} (")[1].split(";\n")[0]

    def text(s):
        return s.replace("''", "'")

    genres = {text(name): int(i) for i, name in re.findall(r"\((\d+), '((?:[^']|'')*)'\)", section("genre"))}
    artists = {text(name): int(i) for i, name in re.findall(r"\((\d+), '((?:[^']|'')*)'\)", section("artist"))}
    albums = {(int(artist), text(title)): int(i)
              for i, artist, title in re.findall(r"\((\d+), (\d+), '((?:[^']|'')*)'", section("album"))}
    spotify_ids = set(re.findall(r"'([0-9A-Za-z]{22})'", section("song")))
    last_song_id = max(int(i) for i in re.findall(r"^  \((\d+),", section("song"), re.M))
    return genres, artists, albums, spotify_ids, last_song_id


def write_csv(name, header, rows):
    with open(OUT / name, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)
    print(f"{name}: {len(rows)} rows")


def main():
    genre_ids, artist_ids, album_ids, existing_songs, last_song_id = read_hand_entered_catalog()
    first_new_genre = len(genre_ids) + 1
    first_new_artist = len(artist_ids) + 1
    first_new_album = len(album_ids) + 1

    with open("data/source/spotify_tracks_pop70.csv", encoding="utf-8") as f:
        tracks = [t for t in csv.DictReader(f) if t["spotify_id"] not in existing_songs]

    # Artist names for each track, in credit order, without repeats.
    for t in tracks:
        names = [n.strip() for n in t["artists"].split(";") if n.strip()]
        t["artist_names"] = list(dict.fromkeys(names))

    # New artists get the next ids, in alphabetical order.
    new_artists = sorted({n for t in tracks for n in t["artist_names"]} - artist_ids.keys(), key=lambda n: (n.lower(), n))
    for i, name in enumerate(new_artists, start=first_new_artist):
        artist_ids[name] = i

    # Albums belong to the track's main (first) artist.
    for t in tracks:
        t["album_key"] = (artist_ids[t["artist_names"][0]], t["album_name"])
    new_albums = sorted({t["album_key"] for t in tracks} - album_ids.keys())
    for i, key in enumerate(new_albums, start=first_new_album):
        album_ids[key] = i

    # Songs get ids from most to least popular.
    tracks.sort(key=lambda t: (-int(t["popularity"]), t["spotify_id"]))
    for i, t in enumerate(tracks, start=last_song_id + 1):
        t["song_id"] = i
        t["genres"] = pick_genres(t["genres"].split(";"))

    used_genres = {g for t in tracks for g in t["genres"]}
    new_genres = sorted(used_genres - genre_ids.keys())
    for i, name in enumerate(new_genres, start=first_new_genre):
        genre_ids[name] = i

    OUT.mkdir(exist_ok=True)
    write_csv("genres.csv", ["genre_id", "genre_name"],
              [(genre_ids[g], g) for g in new_genres])
    write_csv("artists.csv", ["artist_id", "artist_name"],
              [(artist_ids[n], n) for n in new_artists])
    write_csv("albums.csv", ["album_id", "artist_id", "album_title"],
              [(album_ids[key], key[0], key[1]) for key in new_albums])
    write_csv("songs.csv", ["song_id", "album_id", "song_title", "duration_ms", "spotify_id", "popularity"],
              [(t["song_id"], album_ids[t["album_key"]], t["track_name"], t["duration_ms"],
                t["spotify_id"], t["popularity"]) for t in tracks])
    write_csv("song_artist.csv", ["song_id", "artist_id", "artist_position"],
              [(t["song_id"], artist_ids[n], pos)
               for t in tracks for pos, n in enumerate(t["artist_names"], start=1)])
    write_csv("song_genre.csv", ["song_id", "genre_id"],
              [(t["song_id"], genre_ids[g]) for t in tracks for g in sorted(t["genres"], key=genre_ids.get)])


if __name__ == "__main__":
    main()
