# TV guide

Builds a small XMLTV guide once a day for a personal Kodi setup.

- `channel-ids.txt`: guide IDs to keep
- `build-guide.ps1`: downloads public guide data and trims it
- `.github/workflows/build-guide.yml`: runs daily and publishes `tv-guide.xml.gz` to the `guide` release

Contains listing data only. No stream addresses or account details.
