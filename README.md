# droppedneedle

Builds [DroppedNeedle 🌐](https://github.com/DroppedNeedle/DroppedNeedle) **v3** — music
discovery, requests, Usenet acquisition, library management and OpenSubsonic/Jellyfin
serving in one Rust server — from a **pinned commit of the unreleased `v3` branch**.
Deployed by `kubernetes/droppedneedle` as `music.xarif.de`.

## Why a pinned commit and not a release or a fork

- **No v3 image exists upstream.** Docker Hub and GHCR carry v2.x and `dev-<sha>` builds
  of `main` only; the v3 CI builds an image but never pushes it (checked 2026-10-24).
- **v2 is frozen** (last `main` commit 2026-09-28), so starting on v2 would only buy a
  migration later.
- **No maintained fork yet.** The fork machinery (base/dagger-modules `docs/fork.md`)
  follows upstream *releases*; v3 has none, and the patches (`build/patches/`) are a
  few lines each. Revisit when v3.0.0 is released **and** we carry more than such
  small fixes (skill `maintaining-github-forks-on-forgejo`).

## Updating the pinned commit — only on purpose

v3 is still under heavy development, and it **edits migrations it has already shipped**
(last on 2026-10-11). sqlx refuses to boot on a database whose applied migration checksum
changed, so a newer pre-release build can refuse the database an older one created —
and a backup only restores into a build that accepts it.

Renovate therefore tracks the head of `v3` but opens a PR **only after approval in the
dependency dashboard** (`renovate.json`). To move:

1. Back up the database (k8up snapshot + DroppedNeedle's own pre-migration backup; see
   `kubernetes/droppedneedle` README, "Updating").
2. Approve the dashboard item, or set `DROPPEDNEEDLE_COMMIT` by hand — copy it with
   `git rev-parse`, never type it.
3. The build fails on purpose when the commit's `rust-toolchain.toml` no longer matches
   the `rust` base image tag: bump the tag (and its digest) together with the commit.
4. Keep the previous image reference to roll back to; rolling back is only possible while
   the database has not been migrated by the newer build.

Base-image digest refreshes (same tag) are taken automatically: they rebuild the same
upstream commit.

## What differs from upstream's Dockerfile

| | |
| --- | --- |
| Source | fetched by commit inside the build (no checkout as context) and verified |
| Base images | digest-pinned |
| pnpm | the version upstream's Dockerfile at that commit installs (read from it) |
| `python3` | omitted — upstream installs it only to run Python plugins, none run here |
| `/app/VERSION` | `v3-<12-hex commit>`; also baked into the binary as `COMMIT_TAG` |
| `build/patches/` | applied with `git apply` on top of the commit; the build fails if one no longer applies. `0001`: the User-Agent in v2.6.1's form, because musicbrainz.org drops v3's `DroppedNeedle/...` form; `0002`: MusicBrainz paced at 0.5/s, the Cover Art Archive at 1/s and BrainzMash at 4/s instead of 1, 10 and 10; `0003`: the OIDC callback page reads the exchange answer it actually gets (upstream ends a successful SSO sign-in on "Could not reach the server"); `0004`: the login page starts SSO at once (`/login?local` keeps the password form); `0005`: a release tag that is not an MBID (Discogs ids written by beets) is ignored instead of deferring identification forever. Reasons and removal conditions in each patch header |

## License

DroppedNeedle is AGPL-3.0-or-later. This repository and the published image are public;
the exact source of every image is the upstream commit named in `build/Dockerfile` and
`/app/VERSION`.

## Local build

```bash
mise run pipeline   # build + tests, never publishes
mise run image      # build and load as xarif-droppedneedle
```
