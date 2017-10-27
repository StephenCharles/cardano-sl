#!/usr/bin/env bash
set -xe
set -o pipefail

VERSION='1.0'
NAME=${1:-'cardano-sl-static'}
OUTDIR=${NAME}-${VERSION}

nix-build \
        --no-build-output \
        --cores    0 \
        --max-jobs 4 \
        --option binary-caches            "https://cache.nixos.org https://hydra.iohk.io" \
        --option binary-cache-public-keys "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" \
        --out-link "${OUTDIR}" \
        -A ${NAME}

cat <<EOF
Build complete:

  - ./${OUTDIR} is a symlink pointing to the built ${NAME}
  
EOF
