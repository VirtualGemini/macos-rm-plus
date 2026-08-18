#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

normalize_evidence_file() {
  input_file=$1
  repository_root=$2
  test_root=$3
  canonical_test_root=$4

  awk -v repository_root="$repository_root" \
    -v test_root="$test_root" \
    -v canonical_test_root="$canonical_test_root" '
    function replace_literal(text, needle, replacement, position) {
      while (needle != "" && (position = index(text, needle)) != 0) {
        text = substr(text, 1, position - 1) replacement \
          substr(text, position + length(needle))
      }
      return text
    }
    {
      line = replace_literal($0, repository_root, "REPO_ROOT")
      line = replace_literal(line, canonical_test_root, "TEST_ROOT")
      print replace_literal(line, test_root, "TEST_ROOT")
    }
  ' "$input_file"
}
