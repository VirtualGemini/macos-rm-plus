#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

usage() {
  echo "usage: $0 --staged --message-file <path> | --commit <sha> | --range <base-sha> <head-sha>" >&2
  exit 2
}

message=

case "${1-}" in
  --staged)
    if [ "$#" -ne 3 ] || [ "$2" != "--message-file" ]; then
      usage
    fi
    changed_files=$(git diff --cached --name-only --diff-filter=ACMRD)
    message=$(cat "$3")
    ;;
  --commit)
    if [ "$#" -ne 2 ]; then
      usage
    fi
    changed_files=$(git diff-tree --root --no-commit-id --name-only --diff-filter=ACMRD -r "$2")
    message=$(git show -s --format=%B "$2")
    ;;
  --range)
    if [ "$#" -ne 3 ]; then
      usage
    fi
    changed_files=$(git diff --name-only --diff-filter=ACMRD "$2" "$3")
    ;;
  *)
    usage
    ;;
esac

contains_changed_file() {
  candidate=$1
  printf '%s\n' "$changed_files" | grep -Fqx "$candidate"
}

matches_pattern() {
  candidate=$1
  pattern=$2

  case "$pattern" in
    */\*\*)
      prefix=${pattern%/**}
      case "$candidate" in
        "$prefix"/*) return 0 ;;
      esac
      ;;
    *)
      [ "$candidate" = "$pattern" ] && return 0
      ;;
  esac

  return 1
}

rule_matches_changes() {
  rule_index=$1
  path_count=$(/usr/bin/plutil -extract "rules.$rule_index.paths" raw -o - .docs-impact.yml)
  path_index=0

  while [ "$path_index" -lt "$path_count" ]; do
    pattern=$(/usr/bin/plutil -extract "rules.$rule_index.paths.$path_index" raw -o - \
      .docs-impact.yml)
    while IFS= read -r changed_file; do
      if matches_pattern "$changed_file" "$pattern"; then
        return 0
      fi
    done <<EOF
$changed_files
EOF
    path_index=$((path_index + 1))
  done

  return 1
}

rule_count=$(/usr/bin/plutil -extract rules raw -o - .docs-impact.yml)
matching_rules=
rule_index=0

while [ "$rule_index" -lt "$rule_count" ]; do
  if rule_matches_changes "$rule_index"; then
    matching_rules="$matching_rules $rule_index"
  fi
  rule_index=$((rule_index + 1))
done

if [ -z "$matching_rules" ]; then
  exit 0
fi

if [ -n "$message" ]; then
  docs_impact=$(printf '%s\n' "$message" | sed -n 's/^Docs-Impact: //p' | tail -1)
  case "$docs_impact" in
    none) exit 0 ;;
    updated) ;;
    *)
      echo "error: commit message is missing a valid Docs-Impact trailer" >&2
      exit 1
      ;;
  esac
fi

failed=0

for rule_index in $matching_rules; do
  name=$(/usr/bin/plutil -extract "rules.$rule_index.name" raw -o - .docs-impact.yml)
  requirement=$(/usr/bin/plutil -extract "rules.$rule_index.require" raw -o - .docs-impact.yml)
  document_count=$(/usr/bin/plutil -extract "rules.$rule_index.documents" raw -o - \
    .docs-impact.yml)
  document_index=0
  changed_document_count=0
  missing_documents=

  while [ "$document_index" -lt "$document_count" ]; do
    document=$(/usr/bin/plutil -extract "rules.$rule_index.documents.$document_index" raw -o - \
      .docs-impact.yml)
    if contains_changed_file "$document"; then
      changed_document_count=$((changed_document_count + 1))
    else
      if [ -z "$missing_documents" ]; then
        missing_documents=$document
      else
        missing_documents="$missing_documents, $document"
      fi
    fi
    document_index=$((document_index + 1))
  done

  case "$requirement" in
    all)
      if [ "$changed_document_count" -ne "$document_count" ]; then
        echo "error: documentation rule '$name' requires changed documents: $missing_documents" >&2
        failed=1
      fi
      ;;
    any)
      if [ "$changed_document_count" -eq 0 ]; then
        echo "error: documentation rule '$name' requires at least one changed document: $missing_documents" >&2
        failed=1
      fi
      ;;
    *)
      echo "error: documentation rule '$name' has invalid requirement '$requirement'" >&2
      failed=1
      ;;
  esac
done

exit "$failed"
