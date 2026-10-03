import Foundation

struct PinyinItem: Identifiable, Hashable {
    let id: String
    let pinyin: String
    let group: String
    let articulationType: String
    let articulationGuide: String
    let exampleCharacter: String
    let examplePinyin: String
    let exampleMeaning: String
    let speechSample: String
}

enum PinyinSubTab: String, CaseIterable, Identifiable {
    case initials = "Thanh mẫu (Phụ âm đầu)"
    case finals = "Vận mẫu (Vần)"
    case tones = "Thanh điệu & Biến điệu"
    case vocabulary = "Từ vựng Pinyin chuẩn"

    var id: String { rawValue }
}

enum ChinesePinyinData {
    static let zimPinyinURL = URL(string: "https://zim.vn/bang-phien-am-tieng-trung-pinyin")!

    // MARK: - 21 Thanh Mẫu + 2 Bán nguyên âm
    static let initialsGroups: [(name: String, items: [PinyinItem])] = [
        ("Âm hai môi (双唇音)", [
            PinyinItem(id: "b", pinyin: "b", group: "Âm hai môi", articulationType: "Không bật hơi",
                       articulationGuide: "Khép chặt hai môi lại để chặn luồng hơi, sau đó mở môi ra nhanh để âm thoát ra. Luồng hơi rất nhẹ, không bật hơi.",
                       exampleCharacter: "爸爸", examplePinyin: "bàba", exampleMeaning: "bố, ba", speechSample: "爸爸"),
            PinyinItem(id: "p", pinyin: "p", group: "Âm hai môi", articulationType: "Bật hơi mạnh",
                       articulationGuide: "Tương tự âm 'b', khép chặt hai môi, nhưng khi mở môi ra thì bật một luồng hơi thật mạnh ra ngoài.",
                       exampleCharacter: "跑", examplePinyin: "pǎo", exampleMeaning: "chạy", speechSample: "跑"),
            PinyinItem(id: "m", pinyin: "m", group: "Âm hai môi", articulationType: "Âm mũi",
                       articulationGuide: "Khép chặt hai môi, để luồng hơi đi qua khoang mũi và tạo thành âm m mềm mại.",
                       exampleCharacter: "妈妈", examplePinyin: "māma", exampleMeaning: "mẹ, má", speechSample: "妈妈")
        ]),
        ("Âm môi răng (唇齿音)", [
            PinyinItem(id: "f", pinyin: "f", group: "Âm môi răng", articulationType: "Âm xát",
                       articulationGuide: "Răng hàm trên chạm nhẹ vào môi dưới, đẩy luồng hơi qua khe hở để tạo ra âm ma sát gió f.",
                       exampleCharacter: "饭", examplePinyin: "fàn", exampleMeaning: "cơm, bữa ăn", speechSample: "饭")
        ]),
        ("Âm đầu lưỡi giữa (舌尖中音)", [
            PinyinItem(id: "d", pinyin: "d", group: "Âm đầu lưỡi giữa", articulationType: "Không bật hơi",
                       articulationGuide: "Đầu lưỡi chạm vào phần lợi cứng ngay sau răng cửa trên để chặn hơi, sau đó hạ lưỡi xuống nhanh để âm thoát ra. Không bật hơi.",
                       exampleCharacter: "弟弟", examplePinyin: "dìdi", exampleMeaning: "em trai", speechSample: "弟弟"),
            PinyinItem(id: "t", pinyin: "t", group: "Âm đầu lưỡi giữa", articulationType: "Bật hơi mạnh",
                       articulationGuide: "Tương tự âm 'd', đầu lưỡi chạm vào lợi cứng sau răng trên, nhưng khi hạ lưỡi xuống thì bật một luồng hơi mạnh ra ngoài (như th tiếng Việt nhưng bật mạnh hơn).",
                       exampleCharacter: "她", examplePinyin: "tā", exampleMeaning: "cô ấy, chị ấy", speechSample: "她"),
            PinyinItem(id: "n", pinyin: "n", group: "Âm đầu lưỡi giữa", articulationType: "Âm mũi",
                       articulationGuide: "Đầu lưỡi áp vào phần lợi cứng sau răng trên, để luồng hơi đi hoàn toàn qua khoang mũi.",
                       exampleCharacter: "你", examplePinyin: "nǐ", exampleMeaning: "bạn, anh, chị", speechSample: "你"),
            PinyinItem(id: "l", pinyin: "l", group: "Âm đầu lưỡi giữa", articulationType: "Âm bên",
                       articulationGuide: "Đầu lưỡi chạm vào phần lợi cứng sau răng trên, nhưng luồng hơi được thoát ra từ hai bên cạnh lưỡi.",
                       exampleCharacter: "来", examplePinyin: "lái", exampleMeaning: "đến, lại", speechSample: "来")
        ]),
        ("Âm gốc lưỡi / Cuống lưỡi (舌面后音)", [
            PinyinItem(id: "g", pinyin: "g", group: "Âm gốc lưỡi", articulationType: "Không bật hơi",
                       articulationGuide: "Nâng cuống lưỡi lên chạm vào ngạc mềm để chặn hơi, sau đó hạ nhanh cuống lưỡi để âm thoát ra nhẹ nhàng. Đọc như c/k tiếng Việt.",
                       exampleCharacter: "哥哥", examplePinyin: "gēge", exampleMeaning: "anh trai", speechSample: "哥哥"),
            PinyinItem(id: "k", pinyin: "k", group: "Âm gốc lưỡi", articulationType: "Bật hơi mạnh",
                       articulationGuide: "Vị trí giống như âm 'g', nhưng bật luồng hơi mạnh từ cuống họng ra ngoài (kh tiếng Việt bật hơi mạnh).",
                       exampleCharacter: "看", examplePinyin: "kàn", exampleMeaning: "nhìn, xem", speechSample: "看"),
            PinyinItem(id: "h", pinyin: "h", group: "Âm gốc lưỡi", articulationType: "Âm xát nhẹ",
                       articulationGuide: "Cuống lưỡi nâng nhẹ gần chạm ngạc mềm, luồng hơi ma sát đi ra ngoài nhẹ nhàng giữa âm h và kh.",
                       exampleCharacter: "喝", examplePinyin: "hē", exampleMeaning: "uống", speechSample: "喝")
        ]),
        ("Âm mặt lưỡi (舌面前音)", [
            PinyinItem(id: "j", pinyin: "j", group: "Âm mặt lưỡi", articulationType: "Không bật hơi",
                       articulationGuide: "Mặt lưỡi áp sát vào ngạc cứng, chặn hơi rồi hạ nhẹ để âm thoát ra. Không bật hơi (đọc gần như ch nhẹ).",
                       exampleCharacter: "家", examplePinyin: "jiā", exampleMeaning: "nhà, gia đình", speechSample: "家"),
            PinyinItem(id: "q", pinyin: "q", group: "Âm mặt lưỡi", articulationType: "Bật hơi mạnh",
                       articulationGuide: "Vị trí lưỡi giống âm 'j', nhưng bật luồng hơi cực mạnh qua khe mặt lưỡi và vòm họng.",
                       exampleCharacter: "去", examplePinyin: "qù", exampleMeaning: "đi", speechSample: "去"),
            PinyinItem(id: "x", pinyin: "x", group: "Âm mặt lưỡi", articulationType: "Âm xát",
                       articulationGuide: "Mặt lưỡi nâng gần ngạc cứng, đẩy hơi nhẹ nhàng qua khe hở tạo âm xát xì nhẹ (gần như x tiếng Việt).",
                       exampleCharacter: "谢谢", examplePinyin: "xièxie", exampleMeaning: "cảm ơn", speechSample: "谢谢")
        ]),
        ("Âm đầu lưỡi trước (舌尖前音)", [
            PinyinItem(id: "z", pinyin: "z", group: "Âm đầu lưỡi trước", articulationType: "Không bật hơi",
                       articulationGuide: "Đầu lưỡi thẳng chạm nhẹ vào mặt sau răng cửa trên, mở nhẹ khe hở để âm thoát ra không bật hơi.",
                       exampleCharacter: "早", examplePinyin: "zǎo", exampleMeaning: "sớm, buổi sáng", speechSample: "早"),
            PinyinItem(id: "c", pinyin: "c", group: "Âm đầu lưỡi trước", articulationType: "Bật hơi mạnh",
                       articulationGuide: "Vị trí giống âm 'z', nhưng bật luồng hơi mạnh ra trước kẽ răng.",
                       exampleCharacter: "菜", examplePinyin: "cài", exampleMeaning: "món ăn, rau", speechSample: "菜"),
            PinyinItem(id: "s", pinyin: "s", group: "Âm đầu lưỡi trước", articulationType: "Âm xát",
                       articulationGuide: "Đầu lưỡi gần mặt sau răng dưới, luồng hơi ma sát qua kẽ răng tạo âm s nhẹ xì xì.",
                       exampleCharacter: "三", examplePinyin: "sān", exampleMeaning: "số ba", speechSample: "三")
        ]),
        ("Âm đầu lưỡi sau - Uốn lưỡi (舌尖后音)", [
            PinyinItem(id: "zh", pinyin: "zh", group: "Âm uốn lưỡi", articulationType: "Uốn lưỡi, không bật hơi",
                       articulationGuide: "Đầu lưỡi cong lên chạm vào ngạc cứng phía sau lợi trên, thả lỏng mở nhẹ khe hở, không bật hơi (tr tiếng Việt miền Nam tròn vành).",
                       exampleCharacter: "中", examplePinyin: "zhōng", exampleMeaning: "ở giữa, Trung Quốc", speechSample: "中国"),
            PinyinItem(id: "ch", pinyin: "ch", group: "Âm uốn lưỡi", articulationType: "Uốn lưỡi, bật hơi mạnh",
                       articulationGuide: "Đầu lưỡi uốn cong như 'zh', nhưng bật mạnh một luồng hơi dứt khoát ra ngoài.",
                       exampleCharacter: "吃", examplePinyin: "chī", exampleMeaning: "ăn", speechSample: "吃饭"),
            PinyinItem(id: "sh", pinyin: "sh", group: "Âm uốn lưỡi", articulationType: "Uốn lưỡi, âm xát",
                       articulationGuide: "Đầu lưỡi cong lên gần ngạc cứng, luồng hơi ma sát thoát ra ngoài tạo âm s uốn lưỡi dày.",
                       exampleCharacter: "水", examplePinyin: "shuǐ", exampleMeaning: "nước", speechSample: "喝水"),
            PinyinItem(id: "r", pinyin: "r", group: "Âm uốn lưỡi", articulationType: "Uốn lưỡi rung nhẹ",
                       articulationGuide: "Đầu lưỡi cong lên ngạc cứng như 'sh', nhưng dây thanh âm rung nhẹ (giữa r và gi).",
                       exampleCharacter: "热", examplePinyin: "rè", exampleMeaning: "nóng", speechSample: "天气很热")
        ]),
        ("Bán nguyên âm đặc biệt", [
            PinyinItem(id: "y", pinyin: "y (i)", group: "Bán nguyên âm", articulationType: "Nguyên âm mở đầu i",
                       articulationGuide: "Khi đứng đầu âm tiết thay cho i, phát âm mượt mà như i dài.",
                       exampleCharacter: "一", examplePinyin: "yī", exampleMeaning: "số một", speechSample: "一"),
            PinyinItem(id: "w", pinyin: "w (u)", group: "Bán nguyên âm", articulationType: "Nguyên âm mở đầu u",
                       articulationGuide: "Khi đứng đầu âm tiết thay cho u, tròn môi chu ra trước phát âm như u/qu.",
                       exampleCharacter: "五", examplePinyin: "wǔ", exampleMeaning: "số năm", speechSample: "五")
        ])
    ]

    // MARK: - 36 Vận Mẫu (Finals)
    static let finalsGroups: [(name: String, items: [PinyinItem])] = [
        ("Vận mẫu đơn (Nguyên âm đơn - 6)", [
            PinyinItem(id: "a", pinyin: "a", group: "Vận mẫu đơn", articulationType: "Miệng mở rộng",
                       articulationGuide: "Mở miệng rộng nhất, hạ lưỡi xuống vị trí thấp nhất, môi không tròn.",
                       exampleCharacter: "大", examplePinyin: "dà", exampleMeaning: "to, lớn", speechSample: "大"),
            PinyinItem(id: "o", pinyin: "o", group: "Vận mẫu đơn", articulationType: "Tròn môi",
                       articulationGuide: "Tròn môi lại, miệng mở ở mức vừa phải, phần sau của lưỡi hơi nâng lên (đọc như ô/ua).",
                       exampleCharacter: "我", examplePinyin: "wǒ", exampleMeaning: "tôi, mình", speechSample: "我"),
            PinyinItem(id: "e", pinyin: "e", group: "Vận mẫu đơn", articulationType: "Miệng dẹt",
                       articulationGuide: "Khóe miệng kéo dẹt sang hai bên, không tròn môi, miệng mở vừa phải (đọc như ưa/ơ).",
                       exampleCharacter: "喝", examplePinyin: "hē", exampleMeaning: "uống", speechSample: "喝"),
            PinyinItem(id: "i", pinyin: "i", group: "Vận mẫu đơn", articulationType: "Miệng dẹt cười",
                       articulationGuide: "Khóe miệng kéo dẹt sang hai bên như đang cười, miệng chỉ mở khe hẹp, lưỡi đưa cao về phía trước.",
                       exampleCharacter: "一", examplePinyin: "yī", exampleMeaning: "số một", speechSample: "第一"),
            PinyinItem(id: "u", pinyin: "u", group: "Vận mẫu đơn", articulationType: "Môi chu tròn",
                       articulationGuide: "Tròn môi và chu ra phía trước, miệng chỉ mở một khe nhỏ, phần sau của lưỡi nâng cao.",
                       exampleCharacter: "五", examplePinyin: "wǔ", exampleMeaning: "số năm", speechSample: "五个"),
            PinyinItem(id: "v", pinyin: "ü", group: "Vận mẫu đơn", articulationType: "Tròn môi lưỡi trước",
                       articulationGuide: "Giữ vị trí lưỡi của âm 'i', nhưng khẩu hình môi thì tròn và chu ra như âm 'u' (đọc uy).",
                       exampleCharacter: "女", examplePinyin: "nǚ", exampleMeaning: "nữ, phụ nữ", speechSample: "女人")
        ]),
        ("Vận mẫu kép (Nguyên âm đôi)", [
            PinyinItem(id: "ai", pinyin: "ai", group: "Vận mẫu kép", articulationType: "Lướt từ a sang i",
                       articulationGuide: "Bắt đầu từ âm a (miệng rộng), nhanh chóng lướt lên vị trí âm i.",
                       exampleCharacter: "爱", examplePinyin: "ài", exampleMeaning: "yêu", speechSample: "我爱你"),
            PinyinItem(id: "ei", pinyin: "ei", group: "Vận mẫu kép", articulationType: "Lướt từ e sang i",
                       articulationGuide: "Bắt đầu từ âm e (miệng dẹt), nhanh chóng lướt lên vị trí âm i (như ê-i).",
                       exampleCharacter: "谁", examplePinyin: "shéi", exampleMeaning: "ai (người nào)", speechSample: "谁"),
            PinyinItem(id: "ao", pinyin: "ao", group: "Vận mẫu kép", articulationType: "Lướt từ a sang o",
                       articulationGuide: "Bắt đầu từ âm a (miệng rộng), sau đó lướt về vị trí âm o tròn môi.",
                       exampleCharacter: "高", examplePinyin: "gāo", exampleMeaning: "cao", speechSample: "很高"),
            PinyinItem(id: "ou", pinyin: "ou", group: "Vận mẫu kép", articulationType: "Lướt từ o sang u",
                       articulationGuide: "Bắt đầu từ âm o (tròn môi), sau đó lướt về vị trí âm u môi chu hơn (như âu).",
                       exampleCharacter: "口", examplePinyin: "kǒu", exampleMeaning: "miệng, cái", speechSample: "门口"),
            PinyinItem(id: "ia", pinyin: "ia", group: "Vận mẫu kép", articulationType: "Lướt từ i sang a",
                       articulationGuide: "Bắt đầu từ âm i, nhanh chóng lướt mở rộng miệng xuống âm a.",
                       exampleCharacter: "家", examplePinyin: "jiā", exampleMeaning: "gia đình, nhà", speechSample: "回家"),
            PinyinItem(id: "ie", pinyin: "ie", group: "Vận mẫu kép", articulationType: "Lướt từ i sang e",
                       articulationGuide: "Bắt đầu từ âm i, nhanh chóng lướt sang âm e (như iê).",
                       exampleCharacter: "姐", examplePinyin: "jiě", exampleMeaning: "chị gái", speechSample: "姐姐"),
            PinyinItem(id: "ua", pinyin: "ua", group: "Vận mẫu kép", articulationType: "Lướt từ u sang a",
                       articulationGuide: "Bắt đầu từ âm u (tròn môi), nhanh chóng mở rộng sang âm a.",
                       exampleCharacter: "花", examplePinyin: "huā", exampleMeaning: "bông hoa", speechSample: "开花"),
            PinyinItem(id: "uo", pinyin: "uo", group: "Vận mẫu kép", articulationType: "Lướt từ u sang o",
                       articulationGuide: "Bắt đầu từ âm u tròn môi, nhanh chóng chuyển sang âm o.",
                       exampleCharacter: "说", examplePinyin: "shuō", exampleMeaning: "nói", speechSample: "说话"),
            PinyinItem(id: "ue", pinyin: "üe", group: "Vận mẫu kép", articulationType: "Lướt từ ü sang e",
                       articulationGuide: "Bắt đầu từ âm ü (tròn môi, lưỡi trước), nhanh chóng lướt sang âm e.",
                       exampleCharacter: "学", examplePinyin: "xué", exampleMeaning: "học tập", speechSample: "学习")
        ]),
        ("Vận mẫu mũi (Nguyên âm mũi)", [
            PinyinItem(id: "an", pinyin: "an", group: "Vận mẫu mũi", articulationType: "Âm mũi trước",
                       articulationGuide: "Phát âm a rồi nâng đầu lưỡi chạm lợi cứng sau răng trên chặn hơi vào mũi.",
                       exampleCharacter: "看", examplePinyin: "kàn", exampleMeaning: "nhìn, xem", speechSample: "看书"),
            PinyinItem(id: "en", pinyin: "en", group: "Vận mẫu mũi", articulationType: "Âm mũi trước",
                       articulationGuide: "Phát âm e rồi nâng đầu lưỡi chạm lợi cứng sau răng trên (như ơn).",
                       exampleCharacter: "很", examplePinyin: "hěn", exampleMeaning: "rất", speechSample: "很好"),
            PinyinItem(id: "in", pinyin: "in", group: "Vận mẫu mũi", articulationType: "Âm mũi trước",
                       articulationGuide: "Phát âm i rồi nâng đầu lưỡi chạm lợi cứng sau răng trên.",
                       exampleCharacter: "心", examplePinyin: "xīn", exampleMeaning: "trái tim", speechSample: "开心"),
            PinyinItem(id: "ang", pinyin: "ang", group: "Vận mẫu mũi", articulationType: "Âm mũi sau",
                       articulationGuide: "Phát âm a rồi nâng cuống lưỡi chạm ngạc mềm, miệng vẫn mở rộng.",
                       exampleCharacter: "忙", examplePinyin: "máng", exampleMeaning: "bận rộn", speechSample: "很忙"),
            PinyinItem(id: "eng", pinyin: "eng", group: "Vận mẫu mũi", articulationType: "Âm mũi sau",
                       articulationGuide: "Phát âm e rồi nâng cuống lưỡi chạm ngạc mềm chặn hơi ra mũi (như âng).",
                       exampleCharacter: "冷", examplePinyin: "lěng", exampleMeaning: "lạnh", speechSample: "很冷"),
            PinyinItem(id: "ing", pinyin: "ing", group: "Vận mẫu mũi", articulationType: "Âm mũi sau",
                       articulationGuide: "Phát âm i rồi nâng cuống lưỡi chạm ngạc mềm.",
                       exampleCharacter: "听", examplePinyin: "tīng", exampleMeaning: "nghe", speechSample: "听音乐"),
            PinyinItem(id: "ong", pinyin: "ong", group: "Vận mẫu mũi", articulationType: "Âm mũi sau",
                       articulationGuide: "Tròn môi, phần sau lưỡi nâng lên chạm ngạc mềm (như ung).",
                       exampleCharacter: "红", examplePinyin: "hóng", exampleMeaning: "màu đỏ", speechSample: "红色")
        ]),
        ("Vận mẫu uốn lưỡi đặc biệt", [
            PinyinItem(id: "er", pinyin: "er", group: "Vận mẫu đặc biệt", articulationType: "Uốn cong lưỡi",
                       articulationGuide: "Bắt đầu phát âm như âm e, sau đó đồng thời cuốn đầu lưỡi lên trên và về phía sau.",
                       exampleCharacter: "二", examplePinyin: "èr", exampleMeaning: "số hai", speechSample: "第二")
        ])
    ]

    // MARK: - Thanh Điệu (Tones) & Quy tắc biến điệu
    static let tonesInfo = [
        (name: "Thanh 1 (Thanh ngang - 阴平)", symbol: "ā (5-5)",
         desc: "Âm bằng phẳng và duy trì ở độ cao nhất (55). Phát âm đều, dài và ngân nhẹ.",
         example: "mā (妈 - mẹ)"),
        (name: "Thanh 2 (Thanh sắc - 阳平)", symbol: "á (3-5)",
         desc: "Âm đi lên từ mức trung bình lên cao nhất (35). Tương tự dấu sắc nhẹ trong tiếng Việt.",
         example: "má (麻 - mè / vải lanh)"),
        (name: "Thanh 3 (Thanh hỏi - 上声)", symbol: "ǎ (2-1-4)",
         desc: "Âm hạ sâu xuống thấp nhất rồi vút lên cao (214). Cần hạ giọng thật trầm trước khi nâng lên.",
         example: "mǎ (马 - con ngựa)"),
        (name: "Thanh 4 (Thanh rơi - 去声)", symbol: "à (5-1)",
         desc: "Âm rơi dứt khoát từ độ cao 5 xuống thấp nhất 1 (51). Phát âm ngắn, mạnh và dứt khoát.",
         example: "mà (骂 - mắng mỏ)"),
        (name: "Khinh thanh (Thanh nhẹ - 轻声)", symbol: "a (nhẹ)",
         desc: "Không mang dấu thanh điệu, đọc lướt nhanh, nhẹ nhàng, ngắn.",
         example: "ma (吗 - trợ từ nghi vấn)")
    ]

    static let toneSandhiRules = [
        (rule: "Biến điệu hai thanh 3 đi liền nhau",
         content: "Khi hai âm tiết mang thanh 3 đứng cạnh nhau, thanh 3 thứ nhất chuyển thành thanh 2.",
         example: "你好: nǐ hǎo → đọc là [ní hǎo]\n可以: kě yǐ → đọc là [ké yǐ]\n手表: shǒu biǎo → đọc là [shóu biǎo]"),
        (rule: "Biến điệu của chữ '一' (yī)",
         content: "Khi đứng một mình đọc là thanh 1 (yī). Đứng trước thanh 4 đổi thành thanh 2 (yí). Đứng trước thanh 1, 2, 3 đổi thành thanh 4 (yì).",
         example: "一样: yí yàng (trước thanh 4)\n一天: yì tiān (trước thanh 1)\n一起: yì qǐ (trước thanh 3)"),
        (rule: "Biến điệu của chữ '不' (bù)",
         content: "Nguyên bản mang thanh 4 (bù). Khi đứng trước một từ mang thanh 4 khác, đổi thành thanh 2 (bú).",
         example: "不是: bú shì (thay vì bù shì)\n不对: bú duì (thay vì bù duì)\n不好: bù hǎo (giữ nguyên vì hǎo là thanh 3)")
    ]

    // MARK: - 10 Từ vựng giao tiếp cốt lõi theo ZIM
    static let coreVocabulary: [(word: String, pinyin: String, vi: String, en: String)] = [
        ("朋友", "péngyou", "Bạn bè", "Friend"),
        ("什么", "shénme", "Cái gì", "What"),
        ("去", "qù", "Đi", "To go"),
        ("吃", "chī", "Ăn", "To eat"),
        ("家", "jiā", "Nhà, gia đình", "Home, family"),
        ("很", "hěn", "Rất", "Very"),
        ("学校", "xuéxiào", "Trường học", "School"),
        ("对不起", "duìbuqǐ", "Xin lỗi", "I'm sorry"),
        ("谢谢", "xièxie", "Cảm ơn", "Thank you"),
        ("他", "tā", "Anh ấy, ông ấy", "He, him")
    ]
}
