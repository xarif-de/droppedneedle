#!/usr/bin/env bash
# Patch topics and their upstream PRs of a maintained fork (base/dagger-modules docs/fork.md; the
# fork's XARIF.md). Copy verbatim to .xarif/pr.sh; the fork's values live in .xarif/pr.env (read from
# the fork's default branch, so a checkout of a topic — upstream code, no .xarif/ — still finds them).
# A topic lives in refs/xarif/patch/<topic> on Forgejo, not in a branch: a branch push would run the
# upstream's own .github/workflows on our runner. Locally it is the branch patch/<topic>.
# First run from a checkout of the default branch: the script copies itself to
# <git dir>/xarif-pr.sh, which keeps working while a topic (without .xarif/) is checked out.
#   pr.sh list           the topics on Forgejo, each with its series status (local, PR, held back
#                        by pr-after=YYYY-MM-DD, or due)
#   pr.sh get <topic>    check out the topic as the local branch patch/<topic>
#   pr.sh save <topic>   store the local branch patch/<topic> as the topic (refuses to drop commits
#                        stored since your get; a rebase needs FORCE=1). Refuses a topic that starts
#                        from an upstream commit newer than the fork's lock target: a topic is built
#                        on the target, so the next fork-sync composes it at once; NEWER=1 stores it
#                        anyway (an upstream move in progress: fork-sync TARGET= dispatched)
#   pr.sh pull <topic>   take maintainer fixups from the PR head into the topic (fast-forward only)
#   pr.sh push <topic>   publish the topic as the PR head (refuses to drop commits the PR head has;
#                        before the day of its pr-after=, EARLY=1 overrides the hold)
# .xarif/pr.env (KEY=value lines): FORGEJO (fork clone URL), USER_FORK (the GitHub fork the PRs come
# from: "allow edits from maintainers" needs a user-owned fork), UPSTREAM (owner/repo),
# UPSTREAM_BASE (the upstream PR base and the line topics start from, default main), UPSTREAM_URL
# (default https://github.com/$UPSTREAM). BRANCH (default xarif) may come from the env.
set -euo pipefail
self=$(git rev-parse --path-format=absolute --git-common-dir)/xarif-pr.sh
[ "$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")" = "$self" ] || { cp "$0" "$self"; chmod +x "$self"; }
BRANCH=${BRANCH:-xarif}
envfile=$(git show "origin/$BRANCH:.xarif/pr.env" 2>/dev/null || cat .xarif/pr.env 2>/dev/null || true)
val() { sed -n "s/^$1=//p" <<<"$envfile" | tail -1; }
FORGEJO=${FORGEJO:-$(val FORGEJO)}; USER_FORK=${USER_FORK:-$(val USER_FORK)}
UPSTREAM=${UPSTREAM:-$(val UPSTREAM)}; UPSTREAM_BASE=${UPSTREAM_BASE:-$(val UPSTREAM_BASE)}; UPSTREAM_BASE=${UPSTREAM_BASE:-main}
UPSTREAM_URL=${UPSTREAM_URL:-$(val UPSTREAM_URL)}; UPSTREAM_URL=${UPSTREAM_URL:-https://github.com/$UPSTREAM}
[ -n "$FORGEJO" ] || { echo "no FORGEJO: .xarif/pr.env missing on origin/$BRANCH (run 'git fetch origin' once)" >&2; exit 2; }
cmd=${1:?list|get|save|pull|push}
series() { # the series as it is NOW (not a stale local remote-tracking ref)
  git fetch -q "$FORGEJO" "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH"
  git show "origin/$BRANCH:.xarif/series"
}
field() { sed -n "s/.* $1=\([^ ]*\).*/\1/p" <<<" $2"; } # field <key> <series line>
today=$(date -u +%F)
if [ "$cmd" = list ]; then
  s=$(series)
  git ls-remote "$FORGEJO" 'refs/xarif/patch/*' | sed 's#refs/xarif/patch/##' | while read -r sha t; do
    line=$(awk -v t="$t" '$1==t' <<<"$s"); pr=$(field pr "$line"); after=$(field pr-after "$line")
    if [ -z "$line" ]; then st="not in the series"
    elif [ "$pr" = local ]; then st="local (no upstream PR)"
    elif [ -z "$after" ]; then st="PR $pr"
    elif [[ $today < $after ]]; then st="PR $pr held back until $after"
    else st="PR $pr due since $after: open it, then drop pr-after from the series"; fi
    printf '%s %s  %s\n' "$sha" "$t" "$st"
  done
  exit 0
fi
topic=${2:?topic}
[[ $topic =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "bad topic name $topic" >&2; exit 2; }
ours=refs/xarif-seen/patch/$topic # private: a plain `git fetch origin` (and its prune) never touches it
fetch_topic() { # the stored topic → $ours (absent: removed)
  git update-ref -d "$ours" 2>/dev/null || true
  git fetch -q "$FORGEJO" "+refs/xarif/patch/$topic:$ours" 2>/dev/null || true
}
case "$cmd" in
  get)
    fetch_topic
    git rev-parse -q --verify "$ours" >/dev/null || { echo "no topic $topic on Forgejo" >&2; exit 1; }
    if git rev-parse -q --verify "refs/heads/patch/$topic" >/dev/null && ! git merge-base --is-ancestor "patch/$topic" "$ours"; then
      echo "local patch/$topic has commits the stored topic lacks: save them, or delete the branch" >&2; exit 1
    fi
    git switch -q -C "patch/$topic" "$ours"
    echo "on patch/$topic; commit, then: $self save $topic"; exit 0 ;;
  save)
    git rev-parse -q --verify "refs/heads/patch/$topic" >/dev/null || { echo "no local branch patch/$topic" >&2; exit 1; }
    seen=$(git rev-parse -q --verify "$ours" || true) # what your last get/save saw
    if [ -z "$seen" ] && stored=$(git ls-remote "$FORGEJO" "refs/xarif/patch/$topic" | cut -f1) && [ -n "$stored" ]; then
      # never fetched here (no get/save in this checkout): the push lease would fail with git's bare "stale info"
      if [ -z "${FORCE:-}" ]; then
        echo "topic $topic is stored (${stored:0:12}), but this checkout never fetched it (no get/save here):" >&2
        echo "$self get $topic first (replaces patch/$topic), or FORCE=1 $self save $topic to replace the stored one" >&2
        exit 1
      fi
      seen=$stored # FORCE: replace exactly what is stored now
    fi
    if [ -n "$seen" ] && ! git merge-base --is-ancestor "$seen" "patch/$topic" && [ -z "${FORCE:-}" ]; then
      echo "patch/$topic does not contain the stored topic (a rebase?): FORCE=1 $self save $topic" >&2; exit 1
    fi
    # The topic's upstream base must be in the fork's lock target, or the next fork-sync stops on it.
    target=$(series >/dev/null 2>&1; git show "origin/$BRANCH:.xarif/lock" 2>/dev/null | awk '$1=="target"{print $3; exit}' || true)
    if [ -n "$target" ] && [ -z "${NEWER:-}" ]; then
      if git fetch -q "$UPSTREAM_URL" "$UPSTREAM_BASE" 2>/dev/null && git cat-file -e "$target^{commit}" 2>/dev/null; then
        base=$(git merge-base "patch/$topic" FETCH_HEAD || true)
        if [ -n "$base" ] && ! git merge-base --is-ancestor "$base" "$target"; then
          echo "patch/$topic starts from upstream ${base:0:12}, newer than the fork's lock target ${target:0:12}: the next" >&2
          echo "fork-sync would stop on it. Rebase it onto the target (git rebase --onto $target $base patch/$topic)," >&2
          echo "or move the fork first (fork-sync TARGET=<upstream commit>); NEWER=1 $self save $topic stores it anyway" >&2
          exit 1
        fi
      else
        echo "could not read upstream $UPSTREAM_BASE or the lock target; the topic's base is not checked" >&2
      fi
    fi
    git push --force-with-lease="refs/xarif/patch/$topic:$seen" "$FORGEJO" "patch/$topic:refs/xarif/patch/$topic"
    fetch_topic
    echo "topic $topic stored; the next fork-sync picks it up (a new topic also needs its series line, by PR)"; exit 0 ;;
  pull|push) ;;
  *) echo "usage: $self list|get|save|pull|push <topic>" >&2; exit 2 ;;
esac
line=$(series | awk -v t="$topic" '$1==t')
[ -n "$line" ] || { echo "topic $topic is not in the series" >&2; exit 1; }
pr=$(field pr "$line"); after=$(field pr-after "$line")
[ "$pr" != local ] || { echo "topic $topic is local (no upstream PR)" >&2; exit 1; }
if [ "$cmd" = push ] && [ -n "$after" ] && [[ $today < $after ]] && [ -z "${EARLY:-}" ]; then
  echo "topic $topic is held back until $after (pr-after in the series): EARLY=1 $self push $topic publishes it now" >&2; exit 1
fi
fetch_topic
git rev-parse -q --verify "$ours" >/dev/null || { echo "no topic $topic on Forgejo" >&2; exit 1; }
# the PR head, if the branch exists yet (exit 2 = no such branch; anything else is a real error)
if git ls-remote --exit-code "$USER_FORK" "refs/heads/$pr" >/dev/null; then
  git fetch -q "$USER_FORK" "+refs/heads/$pr:refs/pr-head/$topic"
else
  rc=$?; [ "$rc" = 2 ] || { echo "cannot read $USER_FORK (exit $rc)" >&2; exit 1; }
  git update-ref -d "refs/pr-head/$topic" 2>/dev/null || true
fi
theirs=refs/pr-head/$topic
case "$cmd" in
  pull)
    git rev-parse -q --verify "$theirs" >/dev/null || { echo "no PR head $USER_FORK $pr" >&2; exit 1; }
    if git merge-base --is-ancestor "$theirs" "$ours"; then echo "topic $topic already contains the PR head"; exit 0; fi
    git merge-base --is-ancestor "$ours" "$theirs" || { echo "PR head and topic $topic diverged: rebase by hand" >&2; exit 1; }
    # the maintainer's commits are code we did not write: read them before they reach the fork
    git log --stat "$ours..$theirs"
    read -r -p "store these commits as topic $topic? [y/N] " ok
    [ "$ok" = y ] || { echo "nothing stored"; exit 1; }
    git push --force-with-lease="refs/xarif/patch/$topic:$(git rev-parse "$ours")" "$FORGEJO" "$theirs:refs/xarif/patch/$topic"
    echo "topic $topic fast-forwarded to the PR head; the next fork-sync picks it up" ;;
  push)
    seen=$(git rev-parse -q --verify "$theirs" || true)
    if [ -n "$seen" ] && ! git merge-base --is-ancestor "$seen" "$ours"; then
      echo "the PR head has commits topic $topic lacks (maintainer fixups?): run '$self pull $topic' first" >&2; exit 1
    fi
    git push --force-with-lease="refs/heads/$pr:$seen" "$USER_FORK" "$ours:refs/heads/$pr"
    owner=$(sed -E 's#^(https://github\.com/|git@github\.com:|ssh://git@github\.com/)##; s#/.*##' <<<"$USER_FORK")
    [ -n "$seen" ] || echo "open the PR: gh pr create -R $UPSTREAM --head $owner:$pr --base $UPSTREAM_BASE --fill" ;;
esac
