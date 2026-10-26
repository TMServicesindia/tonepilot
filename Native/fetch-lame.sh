#!/usr/bin/env bash
# Fetches LAME 3.100 (LGPL-2.0, the standard open-source MP3 encoder) for Record's MP3 export.
# The archive is checked against the official SHA-256 before it is used. Builds use
# Native/CLame/config.h (Apple/Linux 64-bit) instead of running LAME's configure script.
set -euo pipefail
cd "$(dirname "$0")"
SHA=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
if [ ! -f lame/include/lame.h ]; then
  curl -fsSL -o /tmp/lame-3.100.tar.gz https://downloads.sourceforge.net/project/lame/lame/3.100/lame-3.100.tar.gz
  echo "$SHA  /tmp/lame-3.100.tar.gz" | shasum -a 256 -c -
  rm -rf lame && mkdir lame
  tar xzf /tmp/lame-3.100.tar.gz -C lame --strip-components 1 lame-3.100/include lame-3.100/libmp3lame lame-3.100/COPYING
fi
ls lame/libmp3lame/*.c | wc -l
