#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib/repo.sh"
cd_repo_root

roots=(src/*.sol)
for root in src/*/; do
    case "$root" in
        src/test/ | src/scripts/ | src/proposals/) continue ;;
    esac
    roots+=("$root")
done
roots+=(src/proposals/helpers)

export FOUNDRY_PROFILE=deploy
exec forge build --sizes "${roots[@]}"
