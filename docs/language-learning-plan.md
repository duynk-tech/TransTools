# Kế hoạch học ngoại ngữ trong TransTools

Cập nhật: 02/10/2026. Tài liệu định hướng kiến trúc trải nghiệm và lộ trình kỹ thuật cho tính năng học ngôn ngữ trong app TransTools.

---

## 1. Vị trí trong ứng dụng

Thêm mục **Học ngôn ngữ** vào thanh điều hướng chính (Top Navigation Bar), đứng cạnh các tính năng cốt lõi hiện nay:

$$\text{Cuộc họp} \quad\cdot\quad \text{Sổ tay} \quad\cdot\quad \text{Dịch nhanh} \quad\cdot\quad \mathbf{Học\ ngôn\ ngữ}$$

- **Vị trí UI:** Nằm trên thanh điều hướng đầu trang (`NavTabButton` cạnh "Dịch nhanh", biểu tượng học tập `graduationcap.fill` hoặc `book.pages.fill`).
- **Mục đích:** Đưa việc học trở thành một luồng hành vi tự nhiên mỗi ngày: từ lúc nghe họp hoặc dịch câu → lưu lại → ôn tập và sử dụng được trong công việc.

---

## 2. Kiến trúc chức năng: Người dùng làm gì?

Kế hoạch học được chuyển hóa thành 5 phân hệ trực quan, dễ tiếp cận:

| Phân hệ | Người dùng làm gì | Trọng tâm trải nghiệm |
| :--- | :--- | :--- |
| **Bắt đầu** | Chọn ngôn ngữ, trình độ hiện tại, mục tiêu (công việc / giao tiếp / học tập) và thời gian học mỗi ngày (5 / 10 / 15 phút). | Thiết lập ban đầu nhanh, không rào cản; không bắt buộc nhập API key để bắt đầu. |
| **Hôm nay** | Màn hình chính mỗi ngày: xem và ôn số từ đến hạn (SRS), nghe 1 câu thực tế và luyện 1 tình huống ngắn. | Tạo thói quen hằng ngày ngắn gọn, tập trung; hoàn thành trong 5–10 phút mà không quá tải. |
| **Từ vựng của tôi** | Quản lý kho từ lưu từ bản dịch hoặc cuộc họp, kèm câu gốc theo ngữ cảnh, nghĩa chuẩn, cách đọc và âm thanh phát âm. | Kế thừa và nâng cấp Sổ từ vựng hiện có; lọc theo ngôn ngữ, chuyên ngành và trạng thái nhớ. |
| **Luyện giao tiếp** | Tập giới thiệu bản thân, hỏi đường, viết email xin lịch họp hoặc trao đổi công việc với đối tác. | Học theo nhiệm vụ (Task-based); phản hồi có trọng tâm vào 1–2 điểm cần sửa thay vì chấm điểm chung chung. |
| **Tiến bộ** | Xem biểu đồ từ đã nhớ vững, danh sách lỗi sai thường gặp và các bài / thẻ cần ôn tập lại. | Đo lường thực chất khả năng nhớ lại (retention) và hoàn thành tình huống, không chạy theo chuỗi ngày (streak) ảo. |

---

## 3. Đặc thù ngôn ngữ Đông Á (Nhật – Trung – Hàn)

Không áp đặt cách phiên âm chung (như IPA tiếng Anh) lên tiếng Nhật, Trung, Hàn. Mỗi ngôn ngữ được xử lý với bộ công cụ ngữ âm riêng biệt:

| Ngôn ngữ | Cách đọc & Hiển thị | Bước khởi đầu | Lưu ý kỹ thuật & Sư phạm |
| :--- | :--- | :--- | :--- |
| **Tiếng Nhật** | **Kana / Furigana** đặt trên từ Hán (Kanji); Romaji có tùy chọn bật/tắt | Hiragana, Katakana, chào hỏi, tự giới thiệu | Tách âm đọc theo từ; hỗ trợ nhiều cách đọc (On/Kun) của Kanji; không suy đoán cơ học cách đọc tên riêng. |
| **Tiếng Trung** | **Pinyin** có dấu thanh điệu chuẩn; hỗ trợ chuyển Giản thể / Phồn thể | 4 thanh điệu căn bản, chào hỏi, số đếm, mẫu câu hỏi việc làm | Chú ý chữ đa âm (多音字) theo ngữ cảnh toàn câu; kiểm tra dấu thanh trực quan. |
| **Tiếng Hàn** | **Hangul**, khối âm tiết và hướng dẫn đọc nối âm; Romanization tùy chọn | Nguyên âm, phụ âm, ghép vần, câu chào lịch sự căn bản | Hướng dẫn phát âm âm cuối (Batchim) và quy tắc biến âm; phân biệt kính ngữ và cách nói thân mật trong công việc. |

---

## 4. Nguyên tắc thiết kế & Tích hợp AI

1. **Khởi đầu không cần Key (Zero-AI Barrier):**
   - Người mới bắt đầu học, xem bài mẫu, ôn flashcard và nghe phát âm hệ thống (macOS TTS / AVFoundation) hoàn toàn miễn phí và ngoại tuyến, không cần cấu hình API key.
2. **Vai trò của AI (Khi có API Key):**
   - AI đóng vai trò gia sư hỗ trợ: giải thích sắc thái từ trong ngữ cảnh cuộc họp, sửa câu và giải thích lý do bằng tiếng Việt, dẫn dắt hội thoại đóng vai (roleplay) 3–5 lượt theo mục tiêu cụ thể.
3. **Tôn trọng ngữ cảnh thực:**
   - Từ vựng luôn đi kèm câu thoại gốc từ cuộc họp hoặc văn bản dịch thực tế. Tránh học từ đơn lẻ rời rạc.
4. **Nhắc nhở tinh tế:**
   - Linh vật Chip Chip nhắc nhẹ mục tiêu học ngày khi phù hợp (ví dụ sau khi kết thúc phiên họp hoặc mở app buổi sáng), không làm gián đoạn cuộc họp đang ghi âm.

---

## 5. Lộ trình triển khai (Roadmap)

### Phiên bản 1 (MVP) — Vòng học khép kín ngay từ đầu (Ước lượng: 1–2 tuần)
*Mục tiêu: Đưa tính năng lên app ngay với trải nghiệm hoàn chỉnh từ đầu vào đến ôn tập, tận dụng tối đa nền tảng sẵn có.*
- Thêm tab **Học ngôn ngữ** vào thanh điều hướng chính cạnh Cuộc họp, Sổ tay, Dịch nhanh.
- Hoàn thiện luồng: **Chọn mục tiêu** → **Hôm nay** → **Flashcard ôn cách quãng (SRS)**.
- Nâng cấp **Sổ từ vựng** hiện tại:
  - Bổ sung trường dữ liệu: câu gốc ngữ cảnh, phiên âm chuẩn, trạng thái ôn tập (`dueAt`, `interval`, `repetition`, `easeFactor`).
  - Thuật toán ôn cách quãng (4 mức: Quên / Khó / Nhớ / Dễ) kích hoạt sau khi người dùng tự nhớ lại (Retrieval Practice).
  - Tích hợp phát âm từ và câu ví dụ qua âm thanh hệ thống.
- Di chuyển dữ liệu mượt mà từ Sổ từ vựng cũ sang cấu trúc mới, đảm bảo không mất dữ liệu người dùng.

### Phiên bản 2 — Nhật – Trung – Hàn cho người mới (Ước lượng: 2–3 tuần)
- Tích hợp bộ hiển thị Kana/Furigana (Nhật), Pinyin có thanh (Trung), Hangul & hướng dẫn đọc (Hàn).
- Khóa nhập môn nền tảng: nhận diện mặt chữ, phát âm và các mẫu câu sinh hoạt/công sở cơ bản.
- Tự động gợi ý từ vựng hữu ích sau cuộc họp (người dùng duyệt trước khi lưu, bảo mật thông tin riêng tư).

### Phiên bản 3 — Luyện giao tiếp & AI nâng cao (Ước lượng: 2–3 tuần)
- Đóng vai tình huống (Roleplay): viết email xin lịch họp, giới thiệu bản thân, trao đổi tiến độ dự án, hỏi đường.
- Sửa lỗi câu thông minh: hiển thị câu gốc, câu sửa tự nhiên hơn, giải thích ngắn gọn bằng tiếng Việt.
- Luyện nói tương tác với nhận diện giọng nói hỗ trợ (Speech Recognition), có tùy chọn nghe chậm/bình thường.

### Phiên bản 4 — Đo lường tiến bộ & Tối ưu hóa (Ước lượng: 1–2 tuần)
- Bảng điều khiển "Tiến bộ": đo tỷ lệ nhớ lại sau 7 và 30 ngày, phân tích lỗi ngữ pháp/từ vựng lặp lại.
- Tối ưu hóa hiệu năng, đồng bộ dữ liệu và kiểm soát chi phí token AI.

---

## 6. Cơ sở khoa học & Nguồn học liệu tham khảo

- **Ôn cách quãng (Spaced Repetition):** Kim & Webb (2022) — Phân tích tổng hợp về lợi ích ghi nhớ từ vựng ngôn ngữ thứ hai ([Nguồn nghiên cứu](https://onlinelibrary.wiley.com/doi/abs/10.1111/lang.12479)).
- **Tự nhớ lại (Retrieval Practice):** The Learning Scientists — Đòi hỏi nỗ lực nhớ lại trước khi xem đáp án để củng cố liên kết thần kinh ([Nguồn nghiên cứu](https://www.learningscientists.org/retrieval-practice)).
- **Dạy học theo nhiệm vụ (Task-based Learning & CEFR):** Khung tham chiếu Châu Âu — Đánh giá qua năng lực giải quyết tình huống thực tế ([Hội đồng Châu Âu CEFR](https://www.coe.int/en/web/common-european-framework-reference-languages/action-orientation-in-the-classroom)).
- **Học liệu tiếng Nhật:** Japan Foundation Irodori — Tiếng Nhật trong đời sống và công việc ([Irodori](https://www.irodori.jpf.go.jp/en/)).
- **Học liệu tiếng Hàn:** Nuri Sejong Hakdang — Các khóa đào tạo chuẩn quốc gia Hàn Quốc ([Nuri Sejong](https://www.sejonghakdang.org/opencourse/koreanlecture/list.html)).
- **Học liệu tiếng Trung:** Global Chinese Learning Platform — Nền tảng học tiếng Trung chính thức ([Global Chinese Learning](https://global.chinese-learning.cn/dist/)).
