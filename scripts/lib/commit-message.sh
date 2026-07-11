#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

message_subject() {
  printf '%s\n' "$1" | sed -n '1p'
}

message_trailer() {
  message=$1
  key=$2
  printf '%s\n' "$message" | sed -n "s/^$key: //p" | tail -1
}

message_is_breaking() {
  message=$1
  subject=$(message_subject "$message")
  printf '%s\n' "$subject" | grep -Eq '^.+!:' \
    || printf '%s\n' "$message" | grep -Eq '^BREAKING CHANGE: .+'
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
