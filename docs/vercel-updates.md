# Phát hành qua Vercel

Production: https://trans-tools.vercel.app

- GET /updates/latest.json: manifest phiên bản public; 404/503 được coi là lỗi kiểm tra, không phải đang dùng bản mới nhất.
- GET /download?format=dmg hoặc format=zip: chuyển hướng đến file public Blob.
- /releases: ghi chú bản phát hành hiện tại và link bộ cài.
- macOS app xác minh schema, URL HTTPS của public Blob và SHA256 ZIP trước khi cài đặt.

## GitHub Actions

Repo GitHub vẫn private. Đặt repository secret BLOB_READ_WRITE_TOKEN lấy từ store transtools-releases. Chỉ CI/server giữ token; app và website không chứa token. Secret Vercel đang dùng cho function đọc metadata Blob.

Mỗi lần phát hành:

1. Tăng CFBundleShortVersionString trong Info.plist; tag phải trùng phiên bản này.
2. Thêm docs/release-vX.Y.Z.md nếu muốn ghi chú riêng.
3. Push tag vX.Y.Z. Workflow build ZIP/DMG, tạo GitHub Release private rồi upload bộ cài, checksum, manifest vào public Blob.

Publisher chỉ nhận x.y.z; chặn phát hành cùng phiên bản và downgrade. ZIP/DMG có đường dẫn theo version, không overwrite. Manifest latest chỉ được cập nhật sau khi cả hai file và checksum đã upload xong. Nếu upload dở dang, cần xử lý các file của phiên bản chưa công bố trước khi chạy lại; các phiên bản đã công bố là bất biến.

## Local

- vercel link --project trans-tools
- vercel env pull .env.local
- zsh scripts/package-release.sh
- RELEASE_VERSION=X.Y.Z RELEASE_NOTES_FILE=docs/release-vX.Y.Z.md node --env-file=.env.local scripts/publish-vercel-release.mjs
- vercel deploy --prod

.env.local, .vercel và node_modules đã được ignore; không commit credentials.

Bản app cũ dùng API GitHub private cần cài thủ công DMG mới một lần. Các bản sau dùng manifest public và không cần đăng nhập GitHub.
