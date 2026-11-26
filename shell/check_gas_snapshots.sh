#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/repo.sh"
cd_repo_root

untracked=$(git ls-files --others --exclude-standard -- snapshots/)
if git diff --quiet HEAD -- snapshots/ && [[ -z "$untracked" ]]; then
    exit 0
fi

echo "Gas snapshots are out of date. Run 'pnpm run test:gas' and update the files under snapshots/."
git diff HEAD -- snapshots/
if [[ -n "$untracked" ]]; then
    printf 'New snapshot files:\n%s\n' "$untracked"
fi
exit 1
