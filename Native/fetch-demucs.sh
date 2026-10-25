#!/bin/bash
# Fetches demucs.cpp (MIT) and Eigen (MPL-2.0) sources at pinned commits, and optionally the
# htdemucs 4-source weights (MIT), for the on-device stem separator. Used by CI.
set -euo pipefail
cd "$(dirname "$0")"
DEMUCS_COMMIT=f1206e9adeea103aef4a636b9e62297cf1f8e34e
EIGEN_COMMIT=dd8c71e62852b2fe429edb6682ac91fd1c578a26
if [ ! -d demucs/src ]; then
  rm -rf demucs
  git clone -q https://github.com/sevagh/demucs.cpp.git demucs
  git -C demucs checkout -q "$DEMUCS_COMMIT"
fi
# model.hpp uses std::unique_ptr without including <memory>.
if ! grep -q "#include <memory>" demucs/src/model.hpp; then
  { printf '#include <memory>\n'; cat demucs/src/model.hpp; } > demucs/src/model.hpp.new && mv demucs/src/model.hpp.new demucs/src/model.hpp
fi
python3 "$(dirname "$0")/patch-demucs.py"
if [ ! -d eigen/Eigen ]; then
  rm -rf eigen
  git init -q eigen
  git -C eigen fetch -q --depth 1 https://gitlab.com/libeigen/eigen.git "$EIGEN_COMMIT"
  git -C eigen checkout -q FETCH_HEAD
fi
if [ "${1:-}" = "--weights" ]; then
  mkdir -p ../App/Resources/Models
  W=../App/Resources/Models/ggml-model-htdemucs-4s-f16.bin
  [ -s "$W" ] || curl -fsSL -o "$W" https://huggingface.co/datasets/Retrobear/demucs.cpp/resolve/main/ggml-model-htdemucs-4s-f16.bin
  ls -la "$W"
fi
