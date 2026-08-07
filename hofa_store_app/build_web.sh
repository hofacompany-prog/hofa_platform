#!/usr/bin/env bash
# Build web dùng git commit hash làm version, thay vì tự sửa tay APP_VERSION.
# Ghi cùng 1 giá trị vào web/app-version.json (đọc lúc runtime) và --dart-define
# (đóng cứng vào code lúc build) nên PwaVersionService không bao giờ bị lệch 2 nơi.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f env.json ]; then
  echo "Thiếu env.json — copy env.example.json thành env.json rồi điền giá trị thật trước." >&2
  exit 1
fi

VERSION=$(git rev-parse --short HEAD)
echo "{\"version\": \"$VERSION\"}" > web/app-version.json

flutter build web --dart-define-from-file=env.json --dart-define=APP_VERSION="$VERSION"

echo "Đã build phiên bản $VERSION"
