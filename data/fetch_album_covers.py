"""Fetch album cover image URLs from Spotify's public oEmbed endpoint (no API key needed).

Reads data/source/spotify_tracks_pop70.csv, looks up one track per album, and writes
data/source/album_covers.csv (spotify_id, cover_url). Those links are the cover_url values
in the album inserts, so this only needs to run again if the track list changes.

Usage (from the repo root):
    python data/fetch_album_covers.py
"""
import csv
import json
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

TRACKS_CSV = "data/source/spotify_tracks_pop70.csv"
COVERS_CSV = "data/source/album_covers.csv"
OEMBED_URL = "https://open.spotify.com/oembed?url=https://open.spotify.com/track/{}"


def fetch_cover(track_id):
    for attempt in range(4):
        try:
            with urllib.request.urlopen(OEMBED_URL.format(track_id), timeout=15) as resp:
                return json.load(resp).get("thumbnail_url")
        except Exception:
            time.sleep(2 ** attempt)   # back off on rate limits / network errors
    return None


def main():
    # The dataset has no album ids, so an album is (primary artist, album name),
    # the same key the album table uses. One track is enough to get the cover.
    track_for_album = {}
    with open(TRACKS_CSV, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            primary_artist = row["artists"].split(";")[0].strip()
            track_for_album.setdefault((primary_artist, row["album_name"]), row["spotify_id"])

    track_ids = list(track_for_album.values())
    print(f"Fetching covers for {len(track_ids)} albums...")
    with ThreadPoolExecutor(max_workers=4) as pool:
        urls = list(pool.map(fetch_cover, track_ids))

    found = [(track_id, url) for track_id, url in zip(track_ids, urls) if url]
    with open(COVERS_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["spotify_id", "cover_url"])
        writer.writerows(found)
    print(f"{len(found)} of {len(track_ids)} albums have a cover -> {COVERS_CSV}")


if __name__ == "__main__":
    main()
