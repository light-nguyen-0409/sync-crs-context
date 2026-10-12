#!/usr/bin/env bash

set -euo pipefail

SYNC_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SYNC_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
    printf 'Error: missing configuration file: %s\n' "$ENV_FILE" >&2
    printf 'Create it from .env.example and set PROJECT_DIR.\n' >&2
    exit 1
fi

# shellcheck disable=SC1090
set -a
. "$ENV_FILE"
set +a

if [ -z "${PROJECT_DIR:-}" ]; then
    printf 'Error: PROJECT_DIR is not configured in %s\n' "$ENV_FILE" >&2
    exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
    printf 'Error: required command not found: rsync\n' >&2
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    printf 'Error: project directory does not exist: %s\n' "$PROJECT_DIR" >&2
    exit 1
fi

PROJECT_DIR="$(cd -- "$PROJECT_DIR" && pwd)"

if [ "$PROJECT_DIR" = "$SYNC_DIR" ]; then
    printf 'Error: PROJECT_DIR must not point to the sync repository itself.\n' >&2
    exit 1
fi

for path in AGENTS.md .business-spec .specs .agents; do
    if [ ! -e "$SYNC_DIR/$path" ]; then
        printf 'Error: missing sync source: %s\n' "$SYNC_DIR/$path" >&2
        exit 1
    fi
done

mkdir -p \
    "$PROJECT_DIR/.business-spec" \
    "$PROJECT_DIR/.specs" \
    "$PROJECT_DIR/.agents"

cp "$SYNC_DIR/AGENTS.md" "$PROJECT_DIR/AGENTS.md"
rsync -a "$SYNC_DIR/.business-spec/" "$PROJECT_DIR/.business-spec/"
rsync -a "$SYNC_DIR/.specs/" "$PROJECT_DIR/.specs/"
rsync -a "$SYNC_DIR/.agents/" "$PROJECT_DIR/.agents/"

printf 'CRS context synced to: %s\n' "$PROJECT_DIR"
