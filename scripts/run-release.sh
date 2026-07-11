#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <vX.Y.Z>" >&2
  exit 2
fi

tag=$1

if ! printf '%s\n' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: release tag must use vX.Y.Z" >&2
  exit 1
fi

echo "error: signing, notarization, and publication are disabled until the release ticket is complete" >&2
exit 1
