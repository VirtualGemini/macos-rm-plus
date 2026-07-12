#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

message_subject() {
  printf '%s\n' "$1" | sed -n '1p'
}

message_trailer() {
  message=$1
  key=$2
  printf '%s\n' "$message" | git interpret-trailers --parse \
    | sed -n "s/^$key: //p" \
    | tail -1
}

message_is_breaking() {
  message=$1
  subject=$(message_subject "$message")
  printf '%s\n' "$subject" | grep -Eq '^.+!:' \
    || [ -n "$(message_trailer "$message" BREAKING-CHANGE)" ] \
    || [ -n "$(message_breaking_change "$message")" ]
}

message_breaking_change() {
  printf '%s\n' "$1" | awk '
    BEGIN { block = ""; current = "" }
    /^$/ { if (current != "") { block = current; current = "" }; next }
    { current = current $0 "\n" }
    END {
      if (current != "") block = current
      count = split(block, lines, "\n")
      for (line_number = 1; line_number <= count; line_number++)
        if (lines[line_number] ~ /^BREAKING CHANGE: /) {
          sub(/^BREAKING CHANGE: /, "", lines[line_number]); print lines[line_number]
        }
    }'
}

validate_breaking_ticket_fields() {
  ticket=$1
  for field in \
    '^Breaking change: yes$' \
    '^Approval: approved$' \
    '^Approved by: @[A-Za-z0-9-]+$' \
    '^Approved at: .+' \
    '^Migration plan: .+'; do
    if ! printf '%s\n' "$ticket" | grep -Eq "$field"; then
      printf '%s\n' "$field"
      return 1
    fi
  done
}
