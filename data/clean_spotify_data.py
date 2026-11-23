"""Turn the raw Spotify CSV into one clean CSV per table, ready for \\copy.
"""
import csv
from collections import Counter
from pathlib import Path

OUT = Path("data/spotify")
SOURCE = Path("data/source/spotify_tracks_pop70.csv")

# Spotify tags songs with ~100 small genres ("alt-rock", "deep-house", "k-pop", ...).
# We group them into 21 broad genres. Genre ids follow this order (Pop = 1, ...).
GENRE_MAP = {
    "Pop": ["pop", "dance", "power-pop", "synth-pop", "mandopop", "cantopop"],
    "Rock": ["rock", "alt-rock", "alternative", "hard-rock", "grunge", "psych-rock", "garage",
             "rock-n-roll", "rockabilly", "guitar", "j-rock"],
    "Hip-Hop": ["hip-hop"],
    "Electronic": ["electro", "edm", "house", "progressive-house", "deep-house", "chicago-house",
                   "techno", "trance", "dubstep", "electronic", "idm", "hardstyle", "club", "trip-hop"],
    "Jazz": ["jazz"],
    "R&B": ["r-n-b"],
    "Country": ["country"],
    "Latin": ["latin", "latino", "reggaeton", "salsa", "pagode", "brazil"],
    "Metal": ["metal", "metalcore", "hardcore", "death-metal", "industrial"],
    "Indie": ["indie", "indie-pop"],
    "Reggae": ["reggae", "dancehall", "dub"],
    "Punk": ["punk", "punk-rock", "emo", "ska"],
    "Blues": ["blues"],
    "Classical": ["classical"],
    "Disco": ["disco"],
    "Folk": ["folk", "acoustic", "songwriter", "singer-songwriter"],
    "J-Pop": ["j-pop", "j-dance"],
    "K-Pop": ["k-pop"],
    "Soul": ["soul", "funk", "groove"],
    "Soundtrack": ["pop-film", "show-tunes", "disney", "anime"],
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
    return sorted(counts, key=lambda genre: (-counts[genre], genre))[:2]


def write_csv(name, header, rows):
    with open(OUT / name, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print(name, len(rows))


def main():
    with open(SOURCE, encoding="utf-8") as f:
        tracks = list(csv.DictReader(f))

    for t in tracks:
        names = [n.strip() for n in t["artists"].split(";") if n.strip()]
        t["artist_names"] = list(dict.fromkeys(names))  # keep order, drop dupes
        t["genres"] = pick_genres([g.strip() for g in t["genres"].split(";") if g.strip()])

    artist_ids = {}
    for i, name in enumerate(
        sorted({n for t in tracks for n in t["artist_names"]}, key=lambda n: (n.lower(), n)),
        start=1,
    ):
        artist_ids[name] = i

    for t in tracks:
        t["album_key"] = (artist_ids[t["artist_names"][0]], t["album_name"])
    album_ids = {}
    for i, key in enumerate(sorted({t["album_key"] for t in tracks}), start=1):
        album_ids[key] = i

    tracks.sort(key=lambda t: (-int(t["popularity"]), t["spotify_id"]))
    for i, t in enumerate(tracks, start=1):
        t["song_id"] = i

    genre_ids = {name: i for i, name in enumerate(GENRE_MAP, start=1)}

    OUT.mkdir(exist_ok=True)
    write_csv(
        "genres.csv",
        ["genre_id", "genre_name"],
        [(genre_ids[g], g) for g in sorted(genre_ids, key=genre_ids.get)],
    )
    write_csv(
        "artists.csv",
        ["artist_id", "artist_name"],
        [(artist_ids[n], n) for n in sorted(artist_ids, key=artist_ids.get)],
    )
    write_csv(
        "albums.csv",
        ["album_id", "artist_id", "album_title"],
        [(album_ids[k], k[0], k[1]) for k in sorted(album_ids, key=album_ids.get)],
    )
    write_csv(
        "songs.csv",
        ["song_id", "album_id", "song_title", "duration_ms", "spotify_id", "popularity"],
        [
            (
                t["song_id"],
                album_ids[t["album_key"]],
                t["track_name"],
                t["duration_ms"],
                t["spotify_id"],
                t["popularity"],
            )
            for t in tracks
        ],
    )
    write_csv(
        "song_artist.csv",
        ["song_id", "artist_id", "artist_position"],
        [
            (t["song_id"], artist_ids[n], pos)
            for t in tracks
            for pos, n in enumerate(t["artist_names"], start=1)
        ],
    )
    write_csv(
        "song_genre.csv",
        ["song_id", "genre_id"],
        [
            (t["song_id"], genre_ids[g])
            for t in tracks
            for g in sorted(t["genres"], key=genre_ids.get)
        ],
    )


if __name__ == "__main__":
    main()