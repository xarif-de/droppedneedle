# xarif fork of DroppedNeedle

This is a modified version of [DroppedNeedle](https://github.com/DroppedNeedle/DroppedNeedle)
(the v3 line), licensed under the AGPL-3.0 like the original.
**Modified by xarif since 2026-10-26.** The changes are listed in
[`.xarif/series`](.xarif/series); each one is the ref `refs/xarif/patch/<topic>`.

The fork exists for changes that the upstream project has not taken yet. Each change
that is not our own policy (`pr=local`) is also offered upstream as a pull request — one
marked `pr-after=<day>` not before that day: it runs here first, and upstream may solve it
meanwhile (`.xarif/pr.sh list` shows held and due ones). Once upstream ships a change, the
fork drops it again.

| Where | What |
|---|---|
| [git.xarif.de/docker/droppedneedle](https://git.xarif.de/docker/droppedneedle) | working repository (default branch `xarif`; the build from before the fork: tag `pre-fork/main`) |
| `registry.gitlab.com/xarif/docker/droppedneedle:<tag>` | container image (linux/amd64), deployed by kubernetes/droppedneedle |

## Branches and tags

| Ref | Meaning |
|---|---|
| `xarif` | default branch: an upstream release (v3.x.y) + every patch topic + this infra layer. Changes only through pull requests. |
| `refs/xarif/patch/<topic>` | one change, shaped like an upstream pull request (no xarif files). Not a branch: a branch push would run the upstream's own workflows on our runner. A `patch/*` branch is refused and never used |
| `sync/next` | the next candidate, written by the bot `fork-bot` |
| `v3.x.y-xarif.<m>` | a fork release on upstream release `v3.x.y` |
| `v3.0.0-dev.<n>-xarif.<m>` | an older fork release from the time v3 had no releases (until 2026-11-24): `<n>` is the commit's position on the old `v3` branch; all of them sort before `v3.0.0` |

## How a release happens

The fork follows upstream's releases (`track: release` in `dagger-ci.yaml`; upstream
develops v3 on `main` and releases from it since v3.0.0):

1. `fork-sync` runs every 6 hours. Its target is the newest upstream Release (not a
   pre-release) published at least 24 hours ago. It rebases the patch topics onto the
   target in series order and adds this infra layer. If the result differs from `xarif`,
   it pushes `sync/next` and opens or updates one pull request.
2. `fork-check` runs on that pull request. It recomputes the candidate (it must be
   identical) and runs the upstream test suites: server (fmt, clippy, tests, cargo-deny)
   and frontend (lint, format, type check, vitest).
3. When the checks pass, Forgejo merges the pull request by fast-forward.
4. `fork-tag` tags `xarif` with the next `v3.x.y-xarif.<m>`; `ci` builds and publishes
   the image.

Until 2026-11-24 the fork followed the branch `v3` (`track: branch`, releases
`v3.0.0-dev.<n>-xarif.<m>`). Upstream stopped that branch on 2026-11-13 and moved to
`main`; the first release target was v3.1.0, which contains the last locked v3 commit.

If something needs a human, `fork-bot` opens an issue labelled `fork-blocked` (the sync
stopped) or `fork-advisory` (a security advisory; the sync continues). Each issue says
what happened and what to do. Both kinds close themselves once the cause is gone.

## Change a patch topic

[`.xarif/pr.sh`](.xarif/pr.sh) (from `base/dagger-modules` `templates/fork/`, values in
[`.xarif/pr.env`](.xarif/pr.env)) `get <topic>` checks the topic out as the local branch
`patch/<topic>`; commit, then `save <topic>` stores it. A checked-out topic is upstream code
without `.xarif/`: run the script once from `xarif`, it copies itself to `.git/xarif-pr.sh`,
and use that copy while a topic is checked out (it prints the path). The next `fork-sync`
picks it up (or start it by hand: Actions → fork-sync → Run workflow). `push` / `pull` send
a topic upstream as a pull request and take the maintainer's fixups back (shown for review
first).

## Database migrations

DroppedNeedle checks the checksum of every migration it has applied and refuses to start
if one changed or disappeared, and v3 has edited migrations it had already shipped (last
on 2026-10-11). `fork-sync` therefore stops (`migration-edited`) when a new target changes
or deletes a migration the current one shipped; a human checks what the database needs
and accepts the exact edit in `dagger-ci.yaml` `fork.accepted-migrations`. There is no
rollback to an older release once a newer one migrated the database: fix forward, and
take a database backup before a deployment moves to a new release.

## Automation details

`dagger-ci.yaml` (`fork:` section) and the functions in
[base/dagger-modules](https://git.xarif.de/base/dagger-modules) (`docs/fork.md`).
