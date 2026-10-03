# Bản ghi phát âm dùng trong Chữ & Viết

Ngày nghiên cứu: 03/10/2026. Mục tiêu: người mới không học theo giọng tổng hợp hoặc bản ghi chưa được duyệt. Không tuyên bố chính xác 100% khi chưa có kiểm duyệt chuyên môn.

## Nguồn và tình trạng

| Ngôn ngữ | Nguồn gốc | Phạm vi | Quyền offline / phân phối | Trạng thái trong app |
|---|---|---|---|---|
| Anh | Cambridge Dictionary; British Council Sounds Right | Tên chữ UK/US và âm vị | Cambridge có API/cấp phép riêng; chưa có license. British Council chưa xác minh quyền đóng gói | Liên kết; chưa có bản ghi tên chữ được duyệt |
| Nhật | Japan Foundation HIRAGANA/KATAKANA Memory Hint; Marugoto | Kana, từ và bài học | Marugoto cho tải học liệu, nhưng tải cá nhân không đồng nghĩa quyền phân phối trong app; cần kiểm tra điều khoản từng bộ | Liên kết; chưa đóng gói |
| Trung | Sổ tay chú âm của Bộ Giáo dục Đài Loan | Bopomofo, âm, hoạt hình nét | Trang chính thức công bố CC BY 4.0 cho audio/hoạt hình chú âm; các dữ liệu nét chữ Hán liên quan có điều khoản khác | 37 file gốc đã đóng gói trong mục tham khảo Chú âm riêng; đối chiếu mapping với HTML chính thức. Ghi rõ Mandarin Đài Loan; không gán vào 12 chữ Hán hoặc coi là bài pinyin đại lục |
| Hàn | King Sejong Institute – Hangul Pronunciation Learning; National Institute of Korean Language | Tên chữ, âm trong âm tiết, biến âm | Chưa xác minh quyền tái phân phối từng file | Liên kết; chưa đóng gói |

Nguồn:
- https://dictionary.cambridge.org/license
- https://dictionary.cambridge.org/us/pronunciation/
- https://learnenglish.britishcouncil.org/apps/learnenglish-sounds-right
- https://www.jpf.go.jp/j/kansai/clip/kanamemoryhint/
- https://marugoto.jpf.go.jp/en/download/
- https://language.moe.gov.tw/001/Upload/files/SITE_CONTENT/M0001/deploy/index.html
- https://nuri.iksi.or.kr/practice/learningKoreanPronunciation/kor/index.html
- https://www.korean.go.kr/front_eng/roman/roman_01.do

## Dữ liệu cần hoàn thiện

1. Anh: 26 tên chữ cho UK và US, rồi âm vị và từ đối chiếu. Tên chữ B /biː/ khác âm /b/; không nối bản ghi /b/ và /i/ để giả làm tên B. Không đọc IPA bằng TTS.
2. Nhật: 46 âm cơ bản mỗi bảng; phân biệt chữ viết và âm tương ứng, bổ sung âm đục/âm ghép. Xử lý を, は, へ theo ngữ cảnh; ん cần mẫu ngữ cảnh. Không đọc romaji như tiếng Anh.
3. Trung: lựa chọn biến thể Mandarin trước; thanh mẫu, vận mẫu, bốn thanh và thanh nhẹ; mẫu âm tiết có thanh điệu, biến thanh trong từ/câu. Chữ Hán không phải bảng chữ cái; không lấy audio chú âm gắn tùy tiện vào 12 chữ Hán hiện tại.
4. Hàn: tên 14 phụ âm và 10 nguyên âm cơ bản, âm tiết mẫu, phụ âm căng/bật hơi, batchim và biến âm. Tên chữ và âm trong từ là hai loại dữ liệu khác nhau; không coi romanization là audio chuẩn.

## Điều kiện bật nút nghe

Mỗi bản ghi phải có ID bài học, nội dung chính xác, locale/biến thể, loại tên chữ/âm/từ/câu, người thu, URL nguồn, giấy phép, phiên bản, SHA256 và kết quả duyệt. Chỉ đưa vào bài học khi đúng mapping và quyền sử dụng đã rõ.

Cần hai người duyệt: người bản ngữ và giáo viên/người có chuyên môn ngữ âm. Kiểm tra nội dung, chất lượng âm, nhịp, âm cuối, thanh điệu, tính nhất quán giọng. Duyệt riêng normal/slow; không hạ pitch hoặc kéo âm làm biến dạng mẫu.

Kiểm tra kỹ thuật: file giải mã được, checksum đúng, không clipping, không cắt âm đầu/cuối, thời lượng hợp lý. Các kiểm tra này không chứng minh phát âm đúng.

## Thay đổi hiện tại

Đã bỏ AVSpeechSynthesizer khỏi LetterPronunciationView cho tất cả bốn ngôn ngữ. Nút nghe bản ghi bị khóa với thông báo thiếu bản ghi được duyệt và liên kết nguồn. Không thay bằng TTS ngầm. Phát TTS ở hội thoại/đọc đoạn văn không thuộc thay đổi này.

30 file IPA CC0 đã có vẫn là mục tham khảo riêng, chưa được coi là bộ học tiếng Anh chuẩn hay bản ghi tên chữ. Chưa có bộ đầy đủ cho bất kỳ ngôn ngữ nào; không báo hoàn thành bộ dữ liệu.

## Triển khai 03/10/2026

- Chú âm: 37 WAV nguyên bản (5.41 MB sau giải nén) trong Resources/Pronunciation/Zhuyin, có manifest SHA256, attribution, locale zh-TW. Mapping lấy từ từng hàng HTML của nguồn (play aN + zhStroker ký hiệu), lưu snapshot trong source-review/bopomofo-mapping.html. Phần nghe riêng trong Chữ & Viết tiếng Trung, tốc độ gốc; đổi tab/đóng mục dừng audio. Chỉ xác minh nguồn, mapping và kỹ thuật; chưa có lượt nghe duyệt độc lập. Không bật audio cho 12 chữ Hán.
- Anh: đã tải bản ghi toàn bảng chữ cái của Robotnick2 (2010), 244,610 bytes, CC BY-SA 3.0; xác minh SHA1 công bố. Lưu nguyên OGG + metadata trong source-review/english-alphabet. Không tự tách 26 đoạn hoặc gán UK/US khi chưa được nghe duyệt. Nguồn: https://commons.wikimedia.org/wiki/File:English_alphabet.ogg
- Nhật: bộ ứng viên arsalan-anwari/kana-sounds khai báo CC BY 4.0, ghi nguồn FUN Japanese Learning. Revision 6de3a8ad639b29ad2e58276e6ef51038591cb95f. Thu thập 46 seion trong source-review/japanese-kana; tên file wo lấy seion/wo.mp3, không dùng tokushon/wo.mp3 (ウォ). Chưa xác nhận quyền từ tác giả gốc, chưa nghe duyệt: không đóng gói app. Nguồn: https://huggingface.co/datasets/arsalan-anwari/kana-sounds
- Hàn: đã kiểm tra chính sách Nuri Sejong. Phần lớn học liệu KOGL Type 4 cấm thương mại và sửa đổi, nội dung thiếu dấu KOGL cần trao đổi với đơn vị sở hữu. Không coi khả năng tải file là quyền đưa vào ứng dụng. Nguồn: https://nuri.iksi.or.kr/front/page/etc/copyright/main.do ; https://www.iksi.or.kr/lms/footer/copyright.do

## Công việc còn lại để hoàn thành bộ bài học

1. Có bản ghi từng tên chữ Anh UK/US và quyền phân phối; nghe đối chiếu đặc biệt B/I, R/Z.
2. Xác nhận giấy phép tác giả gốc Kana; người bản ngữ/giáo viên duyệt 46 clip, を/ん và ví dụ theo ngữ cảnh.
3. Có bộ tiếng Hàn cho tên chữ và âm tiết với quyền phù hợp; người bản ngữ duyệt phụ âm bật hơi/căng và batchim.
4. Nếu học Mandarin đại lục, cần bộ pinyin + thanh điệu riêng; không dùng Zhuyin Đài Loan như bộ thay thế hoàn chỉnh.
5. Lập biên bản duyệt từng file với người duyệt, ngày và kết luận; chỉ khi đó mở nút nghe bài học tương ứng.

Không có công cụ nghe trực tiếp/giáo viên trong phiên làm việc này; kiểm tra kỹ thuật và việc phát audio không chứng minh chuẩn phát âm 100%.

## Ưu tiên nguồn chính thống và nghe online

Theo lựa chọn người dùng, bài Chữ & Viết chỉ dùng bản ghi người thật, không fallback TTS/AI. Nút “Nghe tại nguồn” mở trang nhà xuất bản nguyên trạng trong WebKit sheet, người dùng nhấn loa trên trang; đây không phải phát audio trực tiếp hay gói offline. English cấp tên chữ mở mục Cambridge của chữ, cấp từ mở từ ví dụ. Bộ chọn UK/US hướng dẫn chọn loa tương ứng trên trang, không tự bấm loa. Cấp câu chưa có bản ghi câu riêng: UI ghi rõ, chỉ mở nguồn luyện đọc.

Kana chuyển từ trang giới thiệu app Memory Hint sang bảng Hiragana/Katakana MARUGOTO Plus của Japan Foundation để nghe và xem mẫu nét. Korean mở bài phát âm Sejong. Chinese mở bảng Chú âm Bộ Giáo dục Đài Loan, ghi rõ không phải bản ghi chữ Hán đang chọn.

Trang nguồn cần mạng và có thể từ chối WebKit: có nút mở trình duyệt, thử lại khi tải lỗi. Không can thiệp captcha, không tải/scrape audio Cambridge hay bỏ điều khoản nguồn. Sheet dừng tải và xóa trang khi đóng để ngừng nội dung audio. Không nhập/chuyển API key, đoạn hội thoại hay văn bản người dùng sang trang nguồn; chỉ URL bài học có sẵn.

Các clip Commons và Kana cộng đồng vẫn nằm ở thư mục nghiên cứu, không dùng làm audio bài học. Để có nút phát một lần ngay trên bài và offline, vẫn cần nguồn cấp quyền phân phối và kiểm duyệt từng clip.

Kiểm tra UI thực tế: nút Nghe tại nguồn đã bật, chữ I mở đúng URL Cambridge trong sheet. Cambridge hiển thị Cloudflare security verification trong WebKit; chưa xác minh trang audio hoàn tất hoặc nghe được. Cần dùng nút Mở trình duyệt và hoàn tất xác minh trực tiếp nếu nguồn yêu cầu. Không báo đã kiểm thử phát âm Cambridge thành công.
