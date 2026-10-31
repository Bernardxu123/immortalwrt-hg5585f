#!/bin/sh
# Merge the latest pbs05/ponwrt master into the current build tree.
#
# Intended for manual workflow_dispatch builds (not tag/release builds):
# tag builds must stay reproducible and skip this step.
#
# A conflict is a hard failure: do not silently pick a side, because that can
# drop PON/board changes. Resolve locally, commit, push, then rebuild.

set -eu

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/pbs05/ponwrt.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-master}"
UPSTREAM_REF="upstream/$UPSTREAM_BRANCH"

if [ ! -d .git ]; then
	echo "::error::sync-upstream: .git not found in $(pwd)" >&2
	exit 1
fi

if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo false)" = "true" ]; then
	echo "shallow clone detected; fetching full origin history"
	git fetch --unshallow origin
fi

if ! git remote get-url upstream >/dev/null 2>&1; then
	git remote add upstream "$UPSTREAM_URL"
fi

echo "fetching $UPSTREAM_URL $UPSTREAM_BRANCH"
git fetch --no-tags upstream "$UPSTREAM_BRANCH"
upstream_sha=$(git rev-parse "$UPSTREAM_REF")

if git merge-base --is-ancestor "$UPSTREAM_REF" HEAD; then
	echo "upstream already merged: $upstream_sha"
else
	echo "merging $UPSTREAM_REF ($upstream_sha) into $(git rev-parse --short HEAD)"
	if ! git -c user.name="github-actions[bot]" \
		-c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
		merge --no-edit "$UPSTREAM_REF"; then
		echo "::error::pbs05/ponwrt merge conflict; resolve locally and push before rebuilding" >&2
		git merge --abort 2>/dev/null || true
		exit 1
	fi
fi

if [ -n "${GITHUB_ENV:-}" ]; then
	echo "UPSTREAM_SHA=$upstream_sha" >> "$GITHUB_ENV"
fi
git log --oneline -3
