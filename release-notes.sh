#!/usr/bin/env bash
# What changed in a project's next release, for its release notes: the subjects
# of the commits since its last release that touch the game itself, oldest first.
# Run from the project's folder, before tagging.
#
#   ../release-notes.sh metroidvania                         # since the last tag
#   ../release-notes.sh metroidvania metroidvania-v1.2.1     # or since this one
set -euo pipefail

project="${1:?Usage: release-notes.sh <project> [since-tag]}"
since="${2:-$(git tag --list "${project}-v*" --sort=-v:refname | head -n 1)}"
if [[ -z "$since" ]]; then
	exit 0 # the first release: nothing to compare with
fi

changes="$(git log --reverse --format='- %s' "${since}..HEAD" -- . \
	':!tests' ':!docs' ':!ref' ':!*.md' ':!LICENSE' ':!release.sh')"
if [[ -n "$changes" ]]; then
	printf '## Changes since %s\n\n%s\n\n' "${since#"${project}"-}" "$changes"
fi
