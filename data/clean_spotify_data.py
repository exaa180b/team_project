"""Turn the raw Spotify CSV into one clean CSV per table, ready for \\copy.
"""
import csv
from pathlib import Path

OUT = Path("data/spotify")
SOURCE = Path("data/source/spotify_tracks_pop70.csv")


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
        # raw Spotify tags, at most 2
        t["genres"] = [g.strip() for g in t["genres"].split(";") if g.strip()][:2]

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

    genre_ids = {}
    for i, name in enumerate(sorted({g for t in tracks for g in t["genres"]}), start=1):
        genre_ids[name] = i

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