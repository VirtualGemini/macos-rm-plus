#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT/scripts/lib/commit-message.sh"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <commit-message-file>" >&2
  exit 2
fi

message_file=$1
message=$(cat "$message_file")
subject=$(message_subject "$message")
pattern='^(feat|fix|build|refactor|style|chore|test|docs|perf|ci|revert)(\([a-z0-9][a-z0-9._/-]*\))?(!)?: .+'

if ! printf '%s\n' "$subject" | grep -Eq "$pattern"; then
  echo "error: commit subject must follow the repository Conventional Commit format" >&2
  exit 1
fi

if ! grep -Eq '^Signed-off-by: .+ <[^>]+>$' "$message_file"; then
  echo "error: commit message requires a Signed-off-by trailer" >&2
  exit 1
fi

docs_impact=$(message_trailer "$message" Docs-Impact)
case "$docs_impact" in
  updated)
    ;;
  none)
    if ! grep -Eq '^Docs-Impact-Reason: .+' "$message_file"; then
      echo "error: Docs-Impact: none requires Docs-Impact-Reason" >&2
      exit 1
    fi

    docs_approver=$(message_trailer "$message" Docs-Impact-Approved-By)
    if ! printf '%s\n' "$docs_approver" | grep -Eq '^@[A-Za-z0-9-]+$'; then
      echo "error: Docs-Impact: none requires Docs-Impact-Approved-By" >&2
      exit 1
    fi
    ;;
  *)
    echo "error: commit message requires 'Docs-Impact: updated' or 'Docs-Impact: none'" >&2
    exit 1
    ;;
esac

if message_is_breaking "$message"; then
  if [ "$docs_impact" = "none" ]; then
    echo "error: breaking changes cannot declare Docs-Impact: none" >&2
    exit 1
  fi

  if ! grep -Eq '^BREAKING CHANGE: .+' "$message_file"; then
    echo "error: breaking changes require a BREAKING CHANGE trailer" >&2
    exit 1
  fi

  approval=$(message_trailer "$message" Breaking-Approval)
  case "$approval" in
    .scratch/*/issues/*.md)
      ;;
    *)
      echo "error: breaking changes require a local ticket Breaking-Approval path" >&2
      exit 1
      ;;
  esac

  if [ ! -f "$approval" ]; then
    echo "error: breaking approval ticket does not exist: $approval" >&2
    exit 1
  fi

  ticket=$(cat "$approval")
  if missing_field=$(validate_breaking_ticket_fields "$ticket"); then
    :
  else
    echo "error: breaking approval ticket is missing required field: $missing_field" >&2
    exit 1
  fi
fi
