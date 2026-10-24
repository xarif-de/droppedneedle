# DroppedNeedle v3, built from a pinned commit of the UNRELEASED `v3` branch.
#
# ── WHY A BUILD OF AN UNRELEASED COMMIT, AND NOT A FORK ──────────────────────
#
# Upstream publishes no v3 image (Docker Hub and GHCR carry v2.x and `dev-<sha>`
# tags of main only; the v3 CI builds an image but never pushes it), and v2 is
# frozen (last main commit 2026-09-28). The maintained-fork machinery
# (base/dagger-modules docs/fork.md) follows upstream RELEASES, of which v3 has
# none. Our patches (build/patches/: User-Agent, MetaBrainz pacing, OIDC
# sign-in) are a few lines each, small enough to apply here. So: one pinned commit plus those
# patches, rebuilt only when the pin is moved on purpose. Turn this into a
# maintained fork once v3.0.0 is released AND we carry more than such one-liners.
#
# ── WHY THE COMMIT ONLY MOVES ON PURPOSE ─────────────────────────────────────
#
# v3 still edits migrations it has already shipped (last on 2026-10-11) and sqlx
# refuses to boot on a database whose applied migration checksum changed. A newer
# pre-release build can therefore refuse the database an older one created. Move
# DROPPEDNEEDLE_COMMIT only after a database backup, and keep the previous image
# around to roll back to (kubernetes/droppedneedle README, "Updating").
#
# The stages mirror upstream's own Dockerfile at the pinned commit (frontend,
# server, runtime); only the source is fetched here instead of COPYed from a
# checkout, and every base image is digest-pinned.

FROM rust:1.89.0-bookworm@sha256:948f9b08a66e7fe01b03a98ef1c7568292e07ec2e4fe90d88c07bb14563c84ff AS source

# Renovate tracks the head of DROPPEDNEEDLE_REF and proposes a new commit only on
# approval in the dependency dashboard (renovate.json). Copy a commit with
# `git rev-parse`, never type it.
ARG DROPPEDNEEDLE_REF="v3"
ARG DROPPEDNEEDLE_COMMIT="f65ebf0c0a9dca3203f312dc9e6f7444a51c5e0e"

WORKDIR /src
# Local patches on top of the pinned commit (build/patches/, applied in name
# order). `git apply` refuses a patch whose context no longer matches, so a
# commit bump that touches a patched line fails the build here instead of
# shipping without the fix. Each patch's header says why it exists and when it
# can go.
COPY patches/ /patches/
# Fetch exactly one commit by sha; GitHub serves reachable commits by id.
RUN git init -q . && \
    git remote add origin https://github.com/DroppedNeedle/DroppedNeedle.git && \
    git fetch -q --depth 1 origin "$DROPPEDNEEDLE_COMMIT" && \
    git checkout -q FETCH_HEAD && \
    actual="$(git rev-parse HEAD)" && \
    if [ "$actual" != "$DROPPEDNEEDLE_COMMIT" ]; then \
        echo "FATAL: fetched $actual, expected $DROPPEDNEEDLE_COMMIT" >&2; exit 1; \
    fi && \
    for patch in /patches/*.patch; do git apply --verbose "$patch" || exit 1; done && \
    printf 'v3-%s' "$(git rev-parse --short=12 HEAD)" > /src/.commit_tag && \
    git log -1 --format=%cI > /src/.build_date && \
    sed -n 's/.*npm install -g pnpm@\([0-9.]*\).*/\1/p' Dockerfile > /src/.pnpm_version && \
    test -s /src/.pnpm_version && \
    rm -rf .git

FROM node:22-bookworm-slim@sha256:de170b39439eb0e5a3444ad7d60b015614a381e10fecae2e30ec9e735122f38d AS frontend

WORKDIR /app/frontend
# The pnpm version is the one upstream's Dockerfile at the pinned commit installs,
# read from that file, so the lockfile and the package manager move together.
COPY --from=source /src/.pnpm_version /tmp/.pnpm_version
RUN npm install -g "pnpm@$(cat /tmp/.pnpm_version)"
COPY --from=source /src/frontend/ ./
RUN pnpm install --frozen-lockfile
# Bakes the base-path placeholder into root-relative URLs; the server stamps the
# real BASE_PATH in at startup (upstream frontend/svelte.config.js, server/src/web.rs).
ENV DROPPEDNEEDLE_BASE_PATH_PLACEHOLDER=1
RUN pnpm run build

FROM rust:1.89.0-bookworm@sha256:948f9b08a66e7fe01b03a98ef1c7568292e07ec2e4fe90d88c07bb14563c84ff AS builder

# opusic-sys builds a bundled C library through the cmake crate.
RUN apt-get update \
    && apt-get install -y --no-install-recommends cmake \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=source /src/rust-toolchain.toml ./
COPY --from=source /src/server/ ./server/
COPY --from=source /src/sdk/ ./sdk/
COPY --from=source /src/.commit_tag /src/.build_date /tmp/

# Tripwire for a commit bump: the base image's compiler must be the toolchain the
# pinned commit declares. Without it rustup would quietly download another one
# (or the image tag would drift from the source), and the build would no longer
# be the one upstream's CI tested.
RUN want="$(sed -n 's/^channel = "\(.*\)"/\1/p' rust-toolchain.toml)" && \
    have="$(rustc --version | cut -d' ' -f2)" && \
    if [ "$want" != "$have" ]; then \
        echo "FATAL: rust-toolchain.toml wants $want, the base image has $have -- bump the rust image tag" >&2; \
        exit 1; \
    fi

# COMMIT_TAG/BUILD_DATE are read at compile time and reported by the version check.
RUN COMMIT_TAG="$(cat /tmp/.commit_tag)" BUILD_DATE="$(cat /tmp/.build_date)" \
    cargo build --release --locked --manifest-path server/Cargo.toml --bins -p droppedneedle -p droppedneedle-tool

FROM debian:bookworm-slim@sha256:7ff6ba31527b9e336162fa061746c366c4b2032f4d2cff2078bea43f78efe3f8

LABEL org.opencontainers.image.title="DroppedNeedle v3 (xarif build)" \
      org.opencontainers.image.description="DroppedNeedle v3 built from a pinned commit of the unreleased v3 branch" \
      org.opencontainers.image.source="https://git.xarif.de/docker/droppedneedle" \
      org.opencontainers.image.url="https://github.com/DroppedNeedle/DroppedNeedle" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later"

ENV PORT=8688
WORKDIR /app

# ffmpeg for transcoding, gosu for the root-start path of entrypoint.sh, tini as
# PID 1, curl for the health check, tzdata so TZ resolves. No python3: upstream
# installs it only to run Python plugins (its PLUGIN_PYTHON=1 default) and we run
# none; a plugin that ships its own program still works.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl ffmpeg gosu tini tzdata \
    && rm -rf /var/lib/apt/lists/*

# Same baked user as upstream (uid/gid 1000). kubernetes/droppedneedle runs the pod
# as uid 33 instead; entrypoint.sh then skips the user setup and only checks that
# /app/config and /app/cache are writable.
RUN groupadd -r -g 1000 droppedneedle \
    && useradd -r -u 1000 -g droppedneedle -d /app -s /sbin/nologin droppedneedle

COPY --from=builder /app/server/target/release/droppedneedle /usr/local/bin/droppedneedle
COPY --from=builder /app/server/target/release/droppedneedle-tool /usr/local/bin/droppedneedle-tool
# The pristine web UI; the server stamps a copy into /app/cache/static at startup.
COPY --from=frontend /app/frontend/build /app/static
COPY --from=source /src/entrypoint.sh /app/entrypoint.sh
COPY --from=source /src/.commit_tag /app/VERSION

RUN mkdir -p /app/cache /app/config /app/plugins /app/imports \
    && chown droppedneedle:droppedneedle /app/cache /app/config /app/plugins /app/imports \
    && chmod 0755 /app/entrypoint.sh \
    && chmod 0644 /app/VERSION

EXPOSE 8688
ENTRYPOINT ["tini", "--", "/app/entrypoint.sh"]
CMD ["droppedneedle"]
