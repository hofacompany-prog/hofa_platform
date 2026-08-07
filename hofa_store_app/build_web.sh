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


# --pwa-strategy=none: tắt hẳn flutter_service_worker.js (cache asset của Flutter) — service
# worker đó và firebase-messaging-sw.js (đăng ký riêng bởi plugin firebase_messaging) tranh
# nhau cùng 1 scope gốc, gây hiện tượng push đến chập chờn/không ổn định (lúc rơi mất, lúc
# hiện lặp), vì tuỳ thời điểm cập nhật mà không rõ service worker nào đang thực sự kiểm soát
# scope. App không cần cache offline (luôn cần mạng để gọi API thật) nên tắt an toàn, và cơ
# chế PwaVersionService/Cache Storage riêng vẫn tự lo việc cập nhật bản mới.
flutter build web --dart-define-from-file=env.json --dart-define=APP_VERSION="$VERSION" --pwa-strategy=none

echo "Đã build phiên bản $VERSION"
