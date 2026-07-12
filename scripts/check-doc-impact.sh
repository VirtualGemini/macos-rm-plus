#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
. "$ROOT/scripts/lib/commit-message.sh"

configuration_file=.docs-impact.yml
temporary_configuration=
policy_file=.policy-files
temporary_policy=

# shellcheck disable=SC2329 # Invoked by trap.
cleanup() {
  if [ -n "$temporary_configuration" ]; then
    rm -f "$temporary_configuration"
  fi
  if [ -n "$temporary_policy" ]; then rm -f "$temporary_policy"; fi
}
trap cleanup EXIT HUP INT TERM

use_configuration_from_ref() {
  ref=$1
  if git cat-file -e "$ref:.docs-impact.yml" 2>/dev/null; then
    temporary_configuration=$(mktemp)
    git show "$ref:.docs-impact.yml" >"$temporary_configuration"
    configuration_file=$temporary_configuration
  fi
  if git cat-file -e "$ref:.policy-files" 2>/dev/null; then
    temporary_policy=$(mktemp)
    git show "$ref:.policy-files" >"$temporary_policy"
    policy_file=$temporary_policy
  fi
}

usage() {
  echo "usage: $0 --staged --message-file <path> | --commit <sha> | --range <base-sha> <head-sha>" >&2
  exit 2
}

message=
trigger_files=
document_files=

matches_pattern() {
  candidate=$1
  pattern=$2
  # shellcheck disable=SC2254 # Configuration entries are intentional glob patterns.
  case "$candidate" in
    $pattern) return 0 ;;
  esac
  return 1
}

contains_documentation_policy_file() {
  files=$1
  while IFS= read -r candidate; do
    while IFS= read -r pattern; do
      case "$pattern" in '' | \#*) continue ;; esac
      if matches_pattern "$candidate" "$pattern"; then return 0; fi
    done <"$policy_file"
  done <<EOF
$files
EOF
  return 1
}

commit_changed_files() {
  commit=$1
  parent=$(git rev-parse "$commit^1" 2>/dev/null || true)
  if [ -n "$parent" ]; then
    git diff --name-only --diff-filter=ACMRD "$parent" "$commit"
  else
    git diff-tree --root --no-commit-id --name-only --diff-filter=ACMRD -r "$commit"
  fi
}

case "${1-}" in
  --staged)
    if [ "$#" -ne 3 ] || [ "$2" != "--message-file" ]; then
      usage
    fi
    changed_files=$(git diff --cached --name-only --diff-filter=ACMRD)
    document_files=$(git diff --cached --name-only --diff-filter=AM)
    trigger_files=$changed_files
    message=$(cat "$3")
    use_configuration_from_ref HEAD
    ;;
  --commit)
    if [ "$#" -ne 2 ]; then
      usage
    fi
    changed_files=$(commit_changed_files "$2")
    parent_for_docs=$(git rev-parse "$2^1" 2>/dev/null || true)
    if [ -n "$parent_for_docs" ]; then
      document_files=$(git diff --name-only --diff-filter=AM "$parent_for_docs" "$2")
    else
      document_files=$(git diff-tree --root --no-commit-id --name-only --diff-filter=AM -r "$2")
    fi
    trigger_files=$changed_files
    message=$(git show -s --format=%B "$2")
    parent=$(git rev-parse "$2^" 2>/dev/null || true)
    if [ -n "$parent" ]; then
      use_configuration_from_ref "$parent"
    fi
    ;;
  --range)
    if [ "$#" -ne 3 ]; then
      usage
    fi
    merge_base=$(git merge-base "$2" "$3")
    use_configuration_from_ref "$2"
    changed_files=$(git diff --name-only --diff-filter=ACMRD "$merge_base" "$3")
    document_files=$(git diff --name-only --diff-filter=AM "$merge_base" "$3")
    for commit in $(git rev-list --reverse "$merge_base..$3"); do
      commit_message=$(git show -s --format=%B "$commit")
      commit_impact=$(message_trailer "$commit_message" Docs-Impact)
      commit_files=$(commit_changed_files "$commit")
      if [ "$commit_impact" = "none" ] && contains_documentation_policy_file "$commit_files"; then
        echo "error: documentation policy changes cannot use Docs-Impact: none" >&2
        exit 1
      fi
      if [ "$commit_impact" != "none" ]; then
        trigger_files=$(printf '%s\n%s\n' "$trigger_files" "$commit_files")
      fi
    done
    ;;
  *)
    usage
    ;;
esac

contains_changed_document() {
  pattern=$1
  while IFS= read -r candidate; do
    if matches_pattern "$candidate" "$pattern"; then
      return 0
    fi
  done <<EOF
$document_files
EOF
  return 1
}

rule_matches_changes() {
  rule_index=$1
  path_count=$(/usr/bin/plutil -extract "rules.$rule_index.paths" raw -o - "$configuration_file")
  path_index=0

  while [ "$path_index" -lt "$path_count" ]; do
    pattern=$(/usr/bin/plutil -extract "rules.$rule_index.paths.$path_index" raw -o - \
      "$configuration_file")
    while IFS= read -r changed_file; do
      if matches_pattern "$changed_file" "$pattern"; then
        return 0
      fi
    done <<EOF
$trigger_files
EOF
    path_index=$((path_index + 1))
  done

  return 1
}

rule_count=$(/usr/bin/plutil -extract rules raw -o - "$configuration_file")
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
  docs_impact=$(message_trailer "$message" Docs-Impact)
  case "$docs_impact" in
    none)
      if contains_documentation_policy_file "$changed_files"; then
        echo "error: documentation policy changes cannot use Docs-Impact: none" >&2
        exit 1
      fi
      exit 0
      ;;
    updated) ;;
    *)
      echo "error: commit message is missing a valid Docs-Impact trailer" >&2
      exit 1
      ;;
  esac
fi

failed=0

for rule_index in $matching_rules; do
  name=$(/usr/bin/plutil -extract "rules.$rule_index.name" raw -o - "$configuration_file")
  requirement=$(/usr/bin/plutil -extract "rules.$rule_index.require" raw -o - "$configuration_file")
  document_count=$(/usr/bin/plutil -extract "rules.$rule_index.documents" raw -o - \
    "$configuration_file")
  document_index=0
  changed_document_count=0
  missing_documents=

  while [ "$document_index" -lt "$document_count" ]; do
    document=$(/usr/bin/plutil -extract "rules.$rule_index.documents.$document_index" raw -o - \
      "$configuration_file")
    if contains_changed_document "$document"; then
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
