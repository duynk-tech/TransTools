# Tiến độ nâng cấp hệ thống — 03/10/2026

Phạm vi: toàn bộ kế hoạch system-quality-and-vietnamese-learning-plan.md. Đây là nhật ký triển khai, không phải chứng nhận toàn hệ thống đã ổn định. Quyết định mới: dùng CryptoKit AES-GCM, bỏ Keychain làm kho khóa chính; Tiếng Việt lớp 1–5 tự biên soạn.

## Đã triển khai trong mã

Ngày 03/10/2026: theo yêu cầu mới, API key lưu trong credentials.enc mã hóa AES-GCM, ghi atomic, quyền 0600 và cache theo phiên. App không đọc, ghi hoặc xóa Keychain; adapter khôi phục đã loại bỏ vì có thể chặn khởi động. Khóa chỉ nằm trong Keychain có thể cần nhập lại; không xóa bản cũ khi chưa có bản mã hóa. Các ghi chú Keychain bên dưới là lịch sử triển khai. Cơ chế suy khóa theo máy được giữ tương thích; chưa bảo vệ trước người có quyền đọc cả file và mã trên cùng máy. Test test-crypto-storage đã qua với dữ liệu giả, gồm file hỏng không bị ghi đè.

- DATA-01: ghi sổ tay trước khi cập nhật UI, lỗi lưu/xóa/đổi tên hiện rõ; giữ bản sao trước lần ghi; khôi phục bản sao khi file hiện tại lỗi; giữ file lỗi ở bản quarantine trước sửa. Nếu cả hai file đều hỏng, chặn ghi đè. Chưa chuyển actor/DB hoặc version schema.
- SEC-01: API key sang macOS Keychain, không đồng bộ iCloud; xác minh đọc lại trước dọn khóa cũ, giữ dữ liệu cũ khi từ chối truy cập/lỗi; cache theo phiên giảm đọc Keychain trong render. Không log khóa. Chưa kiểm migration thực trên kho cá nhân do máy khóa; test dùng Security API giả.
- AUDIO-01/PERF-01: cache voice inventory trong phiên; slider giữ state cục bộ, lưu khi thả; thay giọng và rời Settings chỉ dừng preview; giọng hiệu ứng không hiện trong danh sách giọng học. Chưa có AudioCoordinator đầy đủ hoặc số đo Instruments.
- UPDATE-01: sau SHA256, yêu cầu đúng một bundle đúng ID và phiên bản; kiểm chữ ký; nếu bản hiện tại có Team ID, bản mới phải cùng Team ID. Bản ad-hoc vẫn chưa có chứng thực danh tính nhà phát hành; cần Developer ID trước phân phối chính thức. Chưa kiểm toàn diện archive traversal/rollback.
- LEARN-02: view Tiếng Việt cho trẻ riêng với lớp 1–5 và bốn mạch; chưa tái dùng CEFR/prompt người lớn, chưa mở bài chưa duyệt.
- LEARN-01/PRIV-01: schema/cổng kiểm metadata học liệu: lớp/phiên bản, tham chiếu, reviewer, quyền, Unicode, media và path; UI đang là khung chuẩn bị, không ghi âm hoặc gửi cloud. Chưa có hồ sơ/parent gate, playback giáo trình hay engine nét.
- Curriculum: chỉ mục nguồn chính thức, 5 bài đọc mới dạng nháp cho lớp 1–5, approved=false; không đưa bản nháp vào bundle.

## Kiểm tra đã chạy

Build cuối release đã qua (37,49 giây), codesign ad-hoc thành công; git diff --check không có lỗi. Bản này chưa kiểm GUI hoặc cài lên máy. Regression scripts:

- test-conversation-save: role/bản dịch/ghi chú/ID ổn định, lỗi ghi/xóa giữ state, backup/khôi phục và chặn ghi đè file hỏng.
- test-keychain-migration: migration xác minh, từ chối giữ khóa cũ, cache và lưu thất bại; dùng khóa giả, không truy cập kho cá nhân.
- test-child-content: draft/lớp/reviewer/media/path chặn publish. Không kiểm chất lượng audio hoặc chữ ký chuyên môn.
- test-learning: SRS, legacy data, trùng từ theo ngôn ngữ, chuyển ngày.
- test-tts/test-speech-errors: giữ contractions, chọn giọng thường, lỗi quota/permission/response.
- test-ai: transport/parser/discovery/retry với mock, không gọi provider bằng key thật.
- test-speech-text: partial/overlap/revision/rotation.
- test-ocr-language: EN/VI/JA/ZH/KO và text rỗng.
- test-update-manifest: schema/version/URL/SHA256/size/zip. Chưa phải kiểm thử end-to-end chữ ký hoặc cài.
- test-native-translation: EN/JA/ZH/KO → VI trên máy, pack installed. Lượt warm 376–482 ms; tiếng Anh cold 1914 ms. Mẫu 1 câu × 2 lượt/ngôn ngữ, không đại diện p95 hoặc live.

Các harness còn trích đoạn production; chưa phải suite test module đầy đủ.

## Chưa hoàn tất — vẫn nằm trong phạm vi

| Ưu tiên | Việc tiếp theo | Phụ thuộc |
|---|---|---|
| P1 | GUI giọng/picker/slider, migration Keychain thực, thay bản app | Mở khóa Mac, đảm bảo không có cuộc họp đang chạy |
| P1 | Đo Instruments, ownership audio hoàn chỉnh, deadline/cancel/cache giới hạn | Fixture thiết bị/network, baseline |
| P1 | Transcript 60 phút/reconnect/sleep/wake, AI schema/task lifecycle, router fallback rõ | Fixture thực và test production module |
| P1 | Update archive/rollback, publisher signing | Developer ID, bộ cài thử có chủ đích |
| P0 trẻ | Ma trận đủ yêu cầu lớp 1–5, audio và mẫu nét được duyệt | Giáo viên, người đọc, phụ lục mẫu chữ gốc |
| P0 trẻ | Hồ sơ/parent gate, gói media offline ký, engine nét, pilot | Gói học liệu được duyệt và consent |
| P1/P2 | Accessibility, cửa sổ nhỏ/dark mode, chẩn đoán riêng tư, CI module hóa | Thiết bị/test UI, triển khai dần |

Không phát hành chương trình trẻ, không chấm phát âm tự động, không thông báo “đã hoàn thiện tất cả”. Bài nháp phục vụ thẩm định; chỉ mục nguồn không thay ma trận đầy đủ. Cần người phụ trách chuyên môn xác nhận trước đưa cho trẻ sử dụng.

Bổ sung AI-01: trả lời hội thoại được decode thành reply/feedback có kiểm tra rỗng/độ dài, thay marker `GÓP Ý:`; deadline toàn tác vụ chat 20 giây, gợi ý 15 giây, hủy request hết hạn, tối đa 3 model thay thế khi 404. Test mock xác minh deadline 1 giây và cancellation. Chưa có benchmark provider thật hoặc kiểm hiệu quả học.

Bổ sung DATA-01: cuộc họp dùng ID riêng mỗi lần bắt đầu; lưu lại giữ tên/ghi chú, hai cuộc họp sát nhau không bị gộp theo khoảng thời gian. Regression test đã qua.

Kiểm tra UI/cài lên /Applications chưa thực hiện: CUA báo Mac đang khóa. Không thay bản đang chạy khi chưa kiểm được có cuộc họp đang hoạt động. Bản build là bản thử nghiệm, chưa bump version hoặc phát hành.

Bản CryptoKit đã build, xác minh chữ ký và cài vào /Applications/TransTools.app. GUI khởi động và AI & Kết nối hiển thị nhãn AES-GCM. Kiểm tra file hiện tại đọc được nhưng không còn khóa Gemini; cần nhập lại trong app vì khóa bản trước nằm trong Keychain và app mới không truy cập kho đó. Không xóa bản Keychain cũ để tránh mất khả năng lấy lại.

## Quyết định bỏ tính năng Tiếng Việt cho trẻ

Theo yêu cầu người dùng, đã bỏ mục Tiếng Việt cho trẻ khỏi menu, view và mã học liệu trong app vì chưa có dữ liệu phát âm chuẩn. Không tiếp tục triển khai chương trình lớp 1–5 trong phạm vi hiện tại. Hồ sơ nghiên cứu/bản nháp trong docs chỉ lưu tham khảo, không phân phối cùng app. Các phần nâng cấp ổn định hệ thống và học ngoại ngữ tiếp tục giữ nguyên.
