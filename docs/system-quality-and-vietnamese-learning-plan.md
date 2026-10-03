# Kế hoạch chất lượng hệ thống & Tiếng Việt cho trẻ

Ngày rà soát: 03/10/2026. Trạng thái: kế hoạch nghiên cứu và triển khai; chưa chứng nhận chương trình học, chưa đánh giá xâm nhập hay kiểm định toàn app.

## 1. Kết luận và phạm vi

Ưu tiên ổn định dữ liệu, audio, tác vụ bất đồng bộ và chất lượng nội dung trước khi mở rộng bài học. Tách hai trải nghiệm: công việc/người lớn và trẻ em. Dùng chung hạ tầng đã kiểm thử nhưng không dùng chung prompt, hồ sơ, lịch sử hay tiêu chí đánh giá.

Rà soát tĩnh tập trung App, Services, AITransport, AIConversation, SpeechSettings, AlphabetLearning, LanguageLearning, Vocabulary, OCR, EdgeTTS, Updater và các bài kiểm tra hiện có. Kho nguồn khoảng 21 nghìn dòng Swift, nhiều tính năng tập trung trong App.swift. Không thể suy ra không có lỗi chỉ từ build thành công. Các vấn đề bên dưới phân biệt điều thấy trong mã với giả thuyết phải đo thực tế. Các thay đổi triển khai được ghi riêng trong system-quality-implementation.md; kế hoạch không đồng nghĩa toàn bộ đã hoàn thành.

## 2. Sổ vấn đề và thứ tự ưu tiên

P0: chặn phát hành nếu có mất dữ liệu, lộ khóa hoặc nội dung trẻ em sai. P1: xử lý trước mở rộng. P2: cải tiến sau nền tảng.

| ID | Mức | Bằng chứng/phạm vi | Vấn đề và việc làm |
|---|---|---|---|
| DATA-01 | P1 | App.swift loadSessions/saveSessionsToDisk/deleteSession | Luồng cũ chỉ print lỗi, sửa state trước khi ghi; luồng conversation mới ghi trước. Hợp nhất repository, giao dịch, báo lỗi UI, backup, khôi phục file lỗi và migration có version. |
| SEC-01 | P1 | Services.swift CredentialStore | Theo quyết định mới giữ CryptoKit AES-GCM, không dùng Keychain. Khóa AES suy ra từ hardware UUID và salt cố định, chưa bảo vệ trước người đọc được file/mã trên cùng máy. Cache, ghi atomic, xác minh đọc lại và không ghi đè kho hỏng đã triển khai; không log key. |
| AUDIO-01 | P1 | Services.swift TTS singleton, SpeechSettings | Các module chia sẻ playback và queue. stop tại đổi giọng/rời view có thể ngắt tác vụ khác. Thêm chủ sở hữu playback và cancel theo session, preview riêng, không phát sinh audio khi đổi cấu hình. |
| PERF-01 | P1 | Slider vừa chuyển state cục bộ; bestVoice vẫn truy vấn AVSpeechSynthesisVoice | Sửa gần đây chưa có số đo. Cache inventory theo phiên, đo MainActor và số lần render; tránh đọc file/key và liệt kê giọng trong render. |
| AUDIO-02 | P1 | EdgeTTSService consumer WebSocket; GeminiSpeech TTS mạng | Edge phụ thuộc endpoint tiêu dùng, không xem là nền tảng có cam kết. Gemini quota/latency có biến động. Adapter, timeout toàn tác vụ, cache hữu hạn, circuit breaker, trạng thái provider thực tế; audio mẫu trẻ chạy offline. |
| LIVE-01 | P1 | AIConversation suffix(12), đọc hết rồi nghe | Hội thoại theo lượt; ngữ cảnh dài bị giới hạn. Tách lịch sử hiển thị/ngữ cảnh, tóm tắt có nguồn, retry không lặp lượt, cảnh báo chưa gửi, kiểm tra echo và thiết bị tai nghe. |
| LIVE-02 | P1 | App speech loop, SpeechTextReconciler | Có xử lý partial nhưng chưa chứng minh không mất nội dung live dài. Tạo fixture ASR sửa câu, ngắt giữa từ, reconnect, suspend, 60 phút; không thay thế câu final bằng partial. |
| AI-01 | P1 | AITransport timeout 60; reply phân tách GÓP Ý | Output text không có schema chặt. Dùng schema + validation, phân loại lỗi, hủy tác vụ, bỏ kết quả cũ, retry có giới hạn; hiển thị ai/provider đang dùng. |
| LEARN-01 | P0 cho trẻ | AlphabetLearning Canvas và dữ liệu hardcode | Chỉ vẽ nét tự do, chưa là hướng dẫn nét chuẩn hoặc chấm viết. Không quảng bá đã dạy viết đúng. Xây kho nét được duyệt, engine riêng và kiểm thử từng chữ. |
| LEARN-02 | P1 | LearningLanguage chỉ EN/JA/ZH/KO; level kiểu A1–C1 | Không có chương trình Tiếng Việt trẻ. Không thêm vi vào enum rồi tái dùng mục tiêu công việc. Tạo curriculum theo lớp, hồ sơ tuổi/lớp và nội dung riêng. |
| LEARN-03 | P1 | Vocabulary interval/ease, tiến độ học | Ôn từ có thuật toán nhưng chưa có đánh giá hiệu quả dài hạn. Test múi giờ, học lại, đổi ngày, không đếm nghe thử là hoàn thành; progress dựa kỹ năng và bằng chứng. |
| OCR-01 | P1 | ScreenOCRService try? fallback | Fallback có thể gửi text sang provider khác. Chính sách rõ, nguồn hiện trên UI, quyền và lỗi chụp; test đa ngôn ngữ/mờ/không có chữ. |
| UPDATE-01 | P1 | Updater có SHA256 nhưng lấy .app đầu tiên trong archive | Hash kiểm tra khớp manifest, không thay chữ ký nhà phát hành. Kiểm bundle ID/version/team signature, HTTPS/host policy, archive an toàn, rollback, cài khi đang lưu/đang họp. Chưa kết luận archive khai thác được. |
| UX-01 | P1 | Các báo cáo giật, label trùng/cắt, fallback khó hiểu | Design system cho button/picker/sidebar, trạng thái nghe/tạo giọng/phát/lỗi riêng; keyboard, VoiceOver, chữ lớn, cửa sổ nhỏ, dark mode. |
| PRIV-01 | P0 cho trẻ | Chưa thấy consent/hồ sơ trẻ trong luồng học | Trẻ dùng offline mặc định; parent gate cho cloud/export/xóa. Không mặc định lưu audio thô; retention và xóa dữ liệu rõ. Phải rà soát quy định trẻ em/dữ liệu cá nhân riêng trước phát hành, chưa kết luận tuân thủ pháp luật. |
| ARCH-01 | P2 | App/Services lớn, singleton và test trích đoạn | Tách module dần bằng interface, dependency injection, clock/mock transport; bổ sung test chạy production modules, không chỉ test snippet. |

## 3. Kiến trúc đích

- UI → view model theo tính năng → use case → repository/service qua interface.
- AudioCoordinator sở hữu capture, ASR, TTS và audio device; một state machine rõ: idle/listening/submitting/generating/playing/cancelled/error. Mỗi request có sessionID/requestID, deadline, cancellation.
- VoiceCatalog: snapshot giọng đã cài, locale/accent/quality rõ; tách giọng macOS, giọng cloud và audio giáo trình. Không sửa cấu hình Accessibility của macOS.
- TranslationRouter: chọn provider theo chính sách, không fallback cloud âm thầm; cache theo text/source/target/domain/provider/model/version.
- StorageRepository actor: atomic writes, migrations, snapshot backup, xóa an toàn và phản hồi thất bại. Cân nhắc SQLite sau benchmark, không đổi DB chỉ vì muốn refactor.
- LearningEngine: curriculum độc lập với UI, lesson graph, attempt log, spaced review và progress theo hồ sơ. Nội dung có schema/version/provenance.
- ContentPipeline: draft → automated validation → giáo viên duyệt → kiểm audio/nét → ký gói → publish; app chỉ tải gói đã duyệt.
- Diagnostics chỉ metric kỹ thuật opt-in; không log text/audio/key trẻ. Cung cấp xuất báo cáo đã che dữ liệu.

## 4. Đo và kiểm chứng trước khi tối ưu

Đo bản hiện tại và sau sửa trên Apple Silicon, thiết bị RAM thấp nếu có, macOS 14 và 15+; Apple Translate chỉ trên hệ điều hành hỗ trợ. Phân biệt cold/warm, offline, quota, mạng chậm, có/không language pack, mic/tai nghe/Bluetooth. Mỗi kết quả ghi máy/OS/provider/ngày/mẫu/số lần, median và p95.

Mục tiêu kỹ thuật đề xuất, chưa phải số đạt:

| Hạng mục | Cổng nghiệm thu |
|---|---|
| UI chọn giọng/kéo slider | p95 phản hồi <=100ms, không MainActor stall >100ms trong kịch bản thử; không ghi mỗi pixel kéo |
| Bài âm thanh local | warm p95 bắt đầu <=200ms; không lặp/chồng khi bấm liên tục |
| TTS cloud | báo chờ ngay, có Dừng; hủy không phát kết quả cũ; deadline hữu hạn đo bằng clock test |
| Dữ liệu | 100% fixture không mất lượt đã xác nhận lưu; lỗi disk hiện rõ; migration rollback được |
| Live transcript | báo word error/omission trên bộ chuẩn từng ngôn ngữ; không đặt mục tiêu 0 lỗi ASR |
| Update | sai hash/signature/ID bị chặn; bản trước khôi phục được khi cài thất bại |
| Năng lượng | đo Instruments 30/60 phút có mascot và không mascot; đặt ngưỡng sau baseline |

Test bắt buộc: app kill trong lúc ghi, hết dung lượng, dữ liệu cũ/hỏng; click start/stop liên tục; đổi provider/ngôn ngữ khi request chạy; mất mạng; từ chối mic/screen; sleep/wake; đổi thiết bị; 429/403/404/timeout; session dài; slider bằng chuột và keyboard. Tests hiện có là điểm xuất phát, chưa đại diện toàn hệ thống.

## 5. Nguồn chương trình Tiếng Việt và giới hạn xác minh

- [Thông tư 32/2018, cơ sở dữ liệu văn bản Bộ GDĐT](https://vbpl.moj.gov.vn/bogiaoducdaotao/Pages/vbpq-toanvan.aspx?ItemID=146721): nền tảng chương trình GDPT. Trang đầy đủ gặp lỗi khi mở trong lần tra cứu; không dùng trích dẫn chưa đọc để chốt ma trận lớp.
- [Bản hợp nhất chương trình tổng thể trên Bộ GDĐT](https://moet.gov.vn/content/vanban/Lists/VBPQ/Attachments/1483/vbhn-chuong-trinh-tong-the.pdf): cơ sở tổ chức môn học; không thay phụ lục môn Ngữ văn/Tiếng Việt.
- [Chương trình môn Ngữ văn được trường Tiểu học Bình Lợi Trung công bố](https://thbinhloitrung.hcm.edu.vn/doi-moi-ctgdpt/chuong-trinh-giao-duc-pho-thong-mon-ngu-van/vbctmb/84846/421496): tìm được trang và liên kết tài liệu, đã mở PDF 110 trang và đối chiếu các mục lớp 1–5; ma trận chi tiết và mẫu chữ vẫn cần kiểm chuyên môn.
- [Thông tư 17/2025](https://datafiles.chinhphu.vn/cpp/files/vbpq/2025/9/17-bgddt.pdf): có sửa đổi chương trình; cần duy trì danh mục văn bản hiện hành, không mặc định bản 2018 là toàn bộ phiên bản hiện tại. Không suy diễn rằng TT này đổi thứ tự dạy chữ Tiếng Việt.
- [Thông tư 27/2020 về đánh giá học sinh tiểu học](https://chinhphu.vn/default.aspx?docid=201006&pageid=27160): tham chiếu đánh giá; app không tự cấp kết quả học tập chính thức.
- [Quyết định 31/2002 về mẫu chữ viết](https://vbpl.vn/bogiaoducdaotao/Pages/ivbpq-thuoctinh.aspx?ItemID=144591): tìm được metadata; phải lấy bản phụ lục gốc, xác minh hiệu lực và mẫu trước khi vẽ nét.

Bước nghiên cứu tiếp theo bắt buộc: lấy toàn văn phụ lục môn học và mẫu chữ từ nguồn chính thức, lưu checksum/ngày/văn bản sửa đổi, lập ma trận yêu cầu cần đạt theo lớp và trang/điều; giáo viên xác nhận. Không dùng blog hoặc AI làm nguồn cuối cho phát âm, nét chữ hay chuẩn đạt.

Chương trình quốc gia và thứ tự bài trong một bộ SGK là hai lớp dữ liệu riêng. Nếu theo bộ sách cụ thể, cần chọn đúng tên/bản/năm và quyền sử dụng văn bản, tranh, audio; không sao chép nguyên sách vào app.

## 6. Thiết kế Tiếng Việt cho trẻ

Phạm vi đã chốt: lớp 1–5, học liệu tự biên soạn theo yêu cầu Bộ GDĐT. Mở bài theo gói đã duyệt, không mở đồng loạt khi chưa kiểm chứng. Giai đoạn làm quen trước lớp 1 tùy chọn, không gắn nhãn chương trình tiểu học bắt buộc. Lớp/tuổi và giọng vùng miền là cấu hình hồ sơ của phụ huynh; không dùng CEFR A1–C1.

Bốn mạch đọc, viết, nói, nghe phải được ánh xạ vào phụ lục chính thức trước phát hành. Lộ trình dưới đây là đề xuất sản phẩm, chưa phải ma trận đã kiểm định:

| Giai đoạn | Nhóm hoạt động |
|---|---|
| Lớp 1 | Làm quen âm/chữ, thanh, ghép tiếng, đọc từ/câu/ngữ liệu phù hợp; viết mẫu, nghe hiểu và nói theo tình huống |
| Lớp 2 | Củng cố đọc, chính tả, đọc hiểu, diễn đạt câu và đoạn ngắn |
| Lớp 3 | Đọc hiểu đa dạng, từ/câu và viết đoạn; kể lại và trình bày |
| Lớp 4–5 | Đọc hiểu sâu hơn, viết có cấu trúc, nói/nghe và phản hồi phù hợp |

### Phát âm và học đọc

Phân biệt tên chữ, âm chữ, đánh vần, đọc tiếng và đọc diễn cảm. Không đưa ký tự đơn vào TTS rồi coi đó là chuẩn dạy âm. Biên soạn audio tên chữ/âm/tiếng/từ/câu riêng bởi người đọc và giáo viên, có transcript khớp, segment/timing và kiểm clipping/loudness. Âm tách rời có thể không tự nhiên; cách hướng dẫn phải được giáo viên quyết định.

Chọn giọng chuẩn của gói bài học; có thể thêm gói vùng miền đã thẩm định. Không chấm sai chỉ vì biến thể vùng miền. Không coi transcript ASR khớp là phát âm đúng: ASR có thể tự sửa tiếng trẻ. Phần nhận xét âm cần bộ dữ liệu trẻ có consent, đánh giá chuyên gia và hiệu chỉnh sai dương/sai âm theo tuổi, tiếng ồn, vùng miền. Khi không chắc: “Mình chưa nghe rõ, con thử lại nhé”, không cho điểm tự tin giả.

Audio giáo trình đã duyệt là nguồn chính. TTS chỉ hỗ trợ nội dung linh hoạt không được dùng thay audio chuẩn khi chưa duyệt. Phát chậm phải giữ cao độ tự nhiên; cần kiểm tai nghe, loa nhỏ và độ rõ từng dấu thanh.

### Hướng dẫn viết

Mẫu chữ thường/hoa và số, kích thước theo ô ly, baseline, vị trí dấu; chỉ chốt từ phụ lục mẫu và giáo viên. Dữ liệu mỗi chữ gồm đường nét vector, hướng, điểm đặt/dừng, nhấc bút, nối nét, nét phụ và dấu. Font hiển thị không tự suy ra được thứ tự nét.

Luồng xem mẫu → animation từng nét → đồ theo → viết độc lập → phản hồi một lỗi dễ hiểu. Tốc độ mẫu chỉnh được, có tua từng nét; trackpad dùng làm quen, giấy/bút cần hướng dẫn tư thế và cầm bút. Không quảng bá trackpad đánh giá đầy đủ kỹ năng viết tay. OCR nhận ra ký tự không chứng minh đúng nét. Không dùng một ngưỡng hình học cho mọi trẻ hoặc mọi thiết bị.

### Bài học, hồ sơ và UI

Mỗi bài có một mục tiêu, hoạt động ngắn, lời hướng dẫn có âm thanh và nút lớn. Không có chat AI tự do mặc định, quảng cáo hay leaderboard gây áp lực. Chip Chip khích lệ cụ thể; tránh animation che chữ, chặn audio hoặc làm nhiễu bài nghe. Phụ huynh xem kỹ năng, lỗi thường gặp và gợi ý luyện tiếp; streak không thay năng lực.

Schema đề xuất: lessonID, revision, grade, curriculumRefs[{document,section,page,outcome}], prerequisites, skillTags, instructions, content, expectedAnswers, audioAssets, strokeAssets, allowedVariants, assessmentPolicy, reviewerIDs, reviewDate, license, checksum. Không có source/reviewer/license thì không được publish.

## 7. Quy trình đảm bảo nội dung

1. Chuyên môn lập ma trận yêu cầu và danh sách biến thể được chấp nhận.
2. Biên soạn bản nháp; AI có thể giúp tác giả, không tự publish.
3. Giáo viên tiểu học duyệt nội dung; chuyên gia âm/giáo viên kiểm audio; người duyệt thứ hai kiểm mẫu chữ và dấu.
4. Validator kiểm tham chiếu, Unicode NFC, media missing, đáp án, đường nét và quyền sử dụng.
5. Thử nghiệm có giám sát với phụ huynh/giáo viên; ghi lỗi rõ, không chỉ hỏi “thích không”.
6. Đóng băng phiên bản, gói offline ký và có rollback. Lỗi nội dung nghiêm trọng rút bài khỏi phân phối.

Cổng phát hành: 100% bài có ma trận, nguồn, quyền và chữ ký duyệt; không còn lỗi nghiêm trọng đã biết; kiểm audio/nét từng asset; hoạt động học cốt lõi chạy không key/mạng; xuất/xóa hồ sơ có parent gate; thử nghiệm và báo cáo chất lượng công khai giới hạn. Không cam kết tuyệt đối “không sai sót”; xây quy trình phát hiện, sửa và thu hồi sai sót.

## 8. Kế hoạch triển khai có phụ thuộc

Ước lượng tuần làm việc, chưa là lịch cam kết; phụ thuộc số người, tài liệu, giáo viên và quyền học liệu.

| Đợt | Thời lượng tham khảo | Đầu ra và điều kiện qua |
|---|---|---|
| A: baseline | 1–2 tuần | Danh mục lỗi có tái hiện, Instruments, fixture audio, data/privacy/update audit; benchmark trước sửa |
| B: ổn định | 2–4 tuần | Repository thống nhất, CryptoKit storage hardening, audio ownership, task lifecycle, regression CI; không mất dữ liệu fixture |
| C: curriculum | 2–4 tuần, song song B | Toàn văn nguồn + ma trận lớp 1 + mẫu chữ + quyền; được chuyên môn duyệt |
| D: prototype | 3–5 tuần sau B/C | 10–15 bài đại diện lớp 1 được duyệt, audio offline, animation nét, hồ sơ trẻ/phụ huynh |
| E: pilot | 2–4 tuần | Thử nghiệm có consent với nhóm nhỏ, phân tích lỗi học/đọc/viết; không mở chấm phát âm tự động nếu chưa đạt |
| F: mở rộng | theo kết quả | Hoàn thành lớp 1 trước, sau đó lớp 2–5 từng gói; mỗi gói có cổng nội dung và test |

Backlog đầu tiên: DATA-01 → AUDIO-01/PERF-01 → SEC-01/UPDATE-01 → curriculum source matrix → offline audio/strokes → pilot. Không refactor toàn bộ cùng lúc; mỗi thay đổi có migration và rollback.

## 9. Quyết định cần chốt trước biên soạn diện rộng

- Đã chốt lớp 1–5.
- Đã chốt học liệu tự biên soạn theo yêu cầu quốc gia; không sao chép một bộ SGK.
- Gói giọng mẫu, biến thể vùng miền và giáo viên thẩm định.
- Có iPad/iPhone/bút hay chỉ Mac: ảnh hưởng thiết kế luyện viết và khả năng đánh giá.
- Cloud cho trẻ: mặc định tắt; chỉ bật từng mục khi phụ huynh cho phép và dữ liệu tối thiểu.

Các quyết định này không ngăn nghiên cứu nền tảng. Chưa xuất bản tính năng cho trẻ trước khi có đầu ra C và kiểm định D/E.
