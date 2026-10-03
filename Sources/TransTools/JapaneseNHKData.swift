import Foundation

struct NHKJapaneseItem: Identifiable, Hashable {
    let id: String
    let hiragana: String
    let katakana: String
    let romaji: String
    let rowGroup: String
    let exampleWord: String
    let exampleReading: String
    let exampleMeaning: String
    let strokeCount: Int
    let mnemonicTip: String

    func displaySymbol(isKatakana: Bool) -> String {
        isKatakana ? katakana : hiragana
    }
}

enum JapaneseCategory: String, CaseIterable, Identifiable {
    case gojuon = "50 Âm cơ bản (Gojūon)"
    case dakuon = "Âm đục & Bán đục (Dakuon)"
    case yoon = "Âm ghép (Yōon)"

    var id: String { rawValue }
}

enum JapaneseNHKData {
    static let nhkHiraganaURL = URL(string: "https://www3.nhk.or.jp/nhkworld/lesson/vi/letters/hiragana.html")!
    static let nhkKatakanaURL = URL(string: "https://www3.nhk.or.jp/nhkworld/lesson/vi/letters/katakana.html")!

    // MARK: - 50 Âm cơ bản Gojuon
    static let gojuonRows: [(name: String, items: [NHKJapaneseItem])] = [
        ("Hàng A (あ行)", [
            NHKJapaneseItem(id: "a", hiragana: "あ", katakana: "ア", romaji: "a", rowGroup: "A",
                            exampleWord: "あめ", exampleReading: "ame", exampleMeaning: "kẹo / mưa",
                            strokeCount: 3, mnemonicTip: "Chữ あ có 3 nét, nét cong tròn bao quanh giống hình quả táo tròn."),
            NHKJapaneseItem(id: "i", hiragana: "い", katakana: "イ", romaji: "i", rowGroup: "A",
                            exampleWord: "いぬ", exampleReading: "inu", exampleMeaning: "con chó",
                            strokeCount: 2, mnemonicTip: "Chữ い gồm 2 nét song song nhẹ như hai cọng dừa hoặc hai cái kim."),
            NHKJapaneseItem(id: "u", hiragana: "う", katakana: "ウ", romaji: "u", rowGroup: "A",
                            exampleWord: "うみ", exampleReading: "umi", exampleMeaning: "biển",
                            strokeCount: 2, mnemonicTip: "Chữ う có nét gạch nhỏ phía trên và một vòm cung cong gập như người đang cúi chào."),
            NHKJapaneseItem(id: "e", hiragana: "え", katakana: "エ", romaji: "e", rowGroup: "A",
                            exampleWord: "えき", exampleReading: "eki", exampleMeaning: "nhà ga",
                            strokeCount: 2, mnemonicTip: "Chữ え nhìn giống hình con chim bồ câu hoặc bậc thang ở nhà ga."),
            NHKJapaneseItem(id: "o", hiragana: "お", katakana: "オ", romaji: "o", rowGroup: "A",
                            exampleWord: "おと", exampleReading: "oto", exampleMeaning: "âm thanh",
                            strokeCount: 3, mnemonicTip: "Chữ お có nét ngang, nét đứng thắt vòng và dấu phẩy bên phải giống quả bóng nảy lên.")
        ]),
        ("Hàng Ka (か行)", [
            NHKJapaneseItem(id: "ka", hiragana: "か", katakana: "カ", romaji: "ka", rowGroup: "Ka",
                            exampleWord: "かさ", exampleReading: "kasa", exampleMeaning: "cái ô",
                            strokeCount: 3, mnemonicTip: "Chữ か giống một người đang mở chiếc ô chống lại gió."),
            NHKJapaneseItem(id: "ki", hiragana: "き", katakana: "キ", romaji: "ki", rowGroup: "Ka",
                            exampleWord: "きく", exampleReading: "kiku", exampleMeaning: "nghe / hoa cúc",
                            strokeCount: 4, mnemonicTip: "Chữ き trông giống chiếc chìa khoá cổ (key)."),
            NHKJapaneseItem(id: "ku", hiragana: "く", katakana: "ク", romaji: "ku", rowGroup: "Ka",
                            exampleWord: "くつ", exampleReading: "kutsu", exampleMeaning: "đôi giày",
                            strokeCount: 1, mnemonicTip: "Chữ く chỉ 1 nét gập nhọn, như chiếc mỏ chim đang mở."),
            NHKJapaneseItem(id: "ke", hiragana: "け", katakana: "ケ", romaji: "ke", rowGroup: "Ka",
                            exampleWord: "けさ", exampleReading: "kesa", exampleMeaning: "sáng nay",
                            strokeCount: 3, mnemonicTip: "Chữ け như thân cây tre mọc thẳng đứng đón nắng mai."),
            NHKJapaneseItem(id: "ko", hiragana: "こ", katakana: "コ", romaji: "ko", rowGroup: "Ka",
                            exampleWord: "こえ", exampleReading: "koe", exampleMeaning: "tiếng / giọng nói",
                            strokeCount: 2, mnemonicTip: "Chữ こ gồm 2 nét ngang trên dưới đối xứng như hai môi đang hé mở phát ra tiếng.")
        ]),
        ("Hàng Sa (さ行)", [
            NHKJapaneseItem(id: "sa", hiragana: "さ", katakana: "サ", romaji: "sa", rowGroup: "Sa",
                            exampleWord: "さかな", exampleReading: "sakana", exampleMeaning: "con cá",
                            strokeCount: 3, mnemonicTip: "Chữ さ giống người đang câu một chú cá nhỏ."),
            NHKJapaneseItem(id: "shi", hiragana: "し", katakana: "シ", romaji: "shi", rowGroup: "Sa",
                            exampleWord: "しお", exampleReading: "shio", exampleMeaning: "muối",
                            strokeCount: 1, mnemonicTip: "Chữ し là một móc câu cá duy nhất uốn mềm mại."),
            NHKJapaneseItem(id: "su", hiragana: "す", katakana: "ス", romaji: "su", rowGroup: "Sa",
                            exampleWord: "すし", exampleReading: "sushi", exampleMeaning: "sushi",
                            strokeCount: 2, mnemonicTip: "Chữ す có nét thắt vòng tròn như cuộn sushi xoắn ốc."),
            NHKJapaneseItem(id: "se", hiragana: "せ", katakana: "セ", romaji: "se", rowGroup: "Sa",
                            exampleWord: "せかい", exampleReading: "sekai", exampleMeaning: "thế giới",
                            strokeCount: 3, mnemonicTip: "Chữ せ giống lưng của một người ngồi nhìn ra thế giới."),
            NHKJapaneseItem(id: "so", hiragana: "そ", katakana: "ソ", romaji: "so", rowGroup: "Sa",
                            exampleWord: "そら", exampleReading: "sora", exampleMeaning: "bầu trời",
                            strokeCount: 1, mnemonicTip: "Chữ そ viết liền nét zích zắc rồi lượn tròn như dải lụa bay trên bầu trời.")
        ]),
        ("Hàng Ta (た行)", [
            NHKJapaneseItem(id: "ta", hiragana: "た", katakana: "タ", romaji: "ta", rowGroup: "Ta",
                            exampleWord: "たこ", exampleReading: "tako", exampleMeaning: "bạch tuộc / con diều",
                            strokeCount: 4, mnemonicTip: "Chữ た gồm nét đứng sổ và chữ こ nhỏ nằm bên cạnh."),
            NHKJapaneseItem(id: "chi", hiragana: "ち", katakana: "チ", romaji: "chi", rowGroup: "Ta",
                            exampleWord: "ちず", exampleReading: "chizu", exampleMeaning: "bản đồ",
                            strokeCount: 2, mnemonicTip: "Chữ ち giống số 5 đảo chiều hay người đang cầm la bàn tìm bản đồ."),
            NHKJapaneseItem(id: "tsu", hiragana: "つ", katakana: "ツ", romaji: "tsu", rowGroup: "Ta",
                            exampleWord: "つき", exampleReading: "tsuki", exampleMeaning: "mặt trăng",
                            strokeCount: 1, mnemonicTip: "Chữ つ là hình ngọn sóng biển hoặc hình vành trăng lưỡi liềm."),
            NHKJapaneseItem(id: "te", hiragana: "て", katakana: "テ", romaji: "te", rowGroup: "Ta",
                            exampleWord: "て", exampleReading: "te", exampleMeaning: "bàn tay",
                            strokeCount: 1, mnemonicTip: "Chữ て nhìn như cổ tay uốn cong mở rộng bàn tay."),
            NHKJapaneseItem(id: "to", hiragana: "と", katakana: "ト", romaji: "to", rowGroup: "Ta",
                            exampleWord: "とり", exampleReading: "tori", exampleMeaning: "con chim",
                            strokeCount: 2, mnemonicTip: "Chữ と trông như cành cây cho chú chim nhỏ đậu lên.")
        ]),
        ("Hàng Na (な行)", [
            NHKJapaneseItem(id: "na", hiragana: "な", katakana: "ナ", romaji: "na", rowGroup: "Na",
                            exampleWord: "なつ", exampleReading: "natsu", exampleMeaning: "mùa hè",
                            strokeCount: 4, mnemonicTip: "Chữ な giống một người đang dang tay nhảy múa mừng mùa hè."),
            NHKJapaneseItem(id: "ni", hiragana: "に", katakana: "ニ", romaji: "ni", rowGroup: "Na",
                            exampleWord: "にく", exampleReading: "niku", exampleMeaning: "thịt",
                            strokeCount: 3, mnemonicTip: "Chữ に có nét sổ trái và hai nét ngang phải như miếng thịt nướng trên vỉ."),
            NHKJapaneseItem(id: "nu", hiragana: "ぬ", katakana: "ヌ", romaji: "nu", rowGroup: "Na",
                            exampleWord: "ぬの", exampleReading: "nuno", exampleMeaning: "tấm vải",
                            strokeCount: 2, mnemonicTip: "Chữ ぬ có nút thắt xoắn đuôi như sợi chỉ đan vào tấm vải."),
            NHKJapaneseItem(id: "ne", hiragana: "ね", katakana: "ネ", romaji: "ne", rowGroup: "Na",
                            exampleWord: "ねこ", exampleReading: "neko", exampleMeaning: "con mèo",
                            strokeCount: 2, mnemonicTip: "Chữ ね có chiếc đuôi xoắn tròn ở cuối như đuôi chú mèo nhỏ."),
            NHKJapaneseItem(id: "no", hiragana: "の", katakana: "ノ", romaji: "no", rowGroup: "Na",
                            exampleWord: "のり", exampleReading: "nori", exampleMeaning: "rong biển",
                            strokeCount: 1, mnemonicTip: "Chữ の chỉ 1 nét xoắn ốc tròn như cuộn rong biển ngon lành.")
        ]),
        ("Hàng Ha (は行)", [
            NHKJapaneseItem(id: "ha", hiragana: "は", katakana: "ハ", romaji: "ha", rowGroup: "Ha",
                            exampleWord: "はな", exampleReading: "hana", exampleMeaning: "bông hoa / cái mũi",
                            strokeCount: 3, mnemonicTip: "Chữ は có cành hoa đứng thẳng và chiếc vòng nở rộ."),
            NHKJapaneseItem(id: "hi", hiragana: "ひ", katakana: "ヒ", romaji: "hi", rowGroup: "Ha",
                            exampleWord: "ひと", exampleReading: "hito", exampleMeaning: "con người",
                            strokeCount: 1, mnemonicTip: "Chữ ひ giống chiếc miệng đang cười toe toét chào con người."),
            NHKJapaneseItem(id: "fu", hiragana: "ふ", katakana: "フ", romaji: "fu", rowGroup: "Ha",
                            exampleWord: "ふね", exampleReading: "fune", exampleMeaning: "con thuyền",
                            strokeCount: 4, mnemonicTip: "Chữ ふ giống cánh buồm đón gió của một chiếc thuyền lướt sóng."),
            NHKJapaneseItem(id: "he", hiragana: "へ", katakana: "ヘ", romaji: "he", rowGroup: "Ha",
                            exampleWord: "へや", exampleReading: "heya", exampleMeaning: "căn phòng",
                            strokeCount: 1, mnemonicTip: "Chữ へ như mái nhà tam giác che chở cho căn phòng ấm cúng."),
            NHKJapaneseItem(id: "ho", hiragana: "ほ", katakana: "ホ", romaji: "ho", rowGroup: "Ha",
                            exampleWord: "ほし", exampleReading: "hoshi", exampleMeaning: "ngôi sao",
                            strokeCount: 4, mnemonicTip: "Chữ ほ có nét ngang che trên đầu và thân cột toả sáng như ngôi sao đêm.")
        ]),
        ("Hàng Ma (ま行)", [
            NHKJapaneseItem(id: "ma", hiragana: "ま", katakana: "マ", romaji: "ma", rowGroup: "Ma",
                            exampleWord: "まめ", exampleReading: "mame", exampleMeaning: "hạt đậu",
                            strokeCount: 3, mnemonicTip: "Chữ ま có 2 nét ngang và nét sổ thắt vòng tròn như hạt đậu nảy mầm."),
            NHKJapaneseItem(id: "mi", hiragana: "み", katakana: "ミ", romaji: "mi", rowGroup: "Ma",
                            exampleWord: "みみ", exampleReading: "mimi", exampleMeaning: "cái tai",
                            strokeCount: 2, mnemonicTip: "Chữ み giống số 21 uốn lượn mềm mại như vành tai lắng nghe."),
            NHKJapaneseItem(id: "mu", hiragana: "む", katakana: "ム", romaji: "mu", rowGroup: "Ma",
                            exampleWord: "むし", exampleReading: "mushi", exampleMeaning: "côn trùng",
                            strokeCount: 3, mnemonicTip: "Chữ む có nét thắt và dấu phẩy như chú bọ nhỏ có đôi cánh xinh."),
            NHKJapaneseItem(id: "me", hiragana: "め", katakana: "メ", romaji: "me", rowGroup: "Ma",
                            exampleWord: "め", exampleReading: "me", exampleMeaning: "mắt",
                            strokeCount: 2, mnemonicTip: "Chữ め trông như hình con mắt sáng long lanh."),
            NHKJapaneseItem(id: "mo", hiragana: "も", katakana: "モ", romaji: "mo", rowGroup: "Ma",
                            exampleWord: "もり", exampleReading: "mori", exampleMeaning: "khu rừng",
                            strokeCount: 3, mnemonicTip: "Chữ も giống lưỡi câu cá có thêm 2 chiếc gai gai nhỏ.")
        ]),
        ("Hàng Ya (や行)", [
            NHKJapaneseItem(id: "ya", hiragana: "や", katakana: "ヤ", romaji: "ya", rowGroup: "Ya",
                            exampleWord: "やま", exampleReading: "yama", exampleMeaning: "ngọn núi",
                            strokeCount: 3, mnemonicTip: "Chữ や như con thuyền nhỏ đậu dưới chân ngọn núi hùng vĩ."),
            NHKJapaneseItem(id: "yu", hiragana: "ゆ", katakana: "ユ", romaji: "yu", rowGroup: "Ya",
                            exampleWord: "ゆき", exampleReading: "yuki", exampleMeaning: "tuyết rơi",
                            strokeCount: 2, mnemonicTip: "Chữ ゆ mềm mại như vết trượt tuyết trắng xoá."),
            NHKJapaneseItem(id: "yo", hiragana: "よ", katakana: "ヨ", romaji: "yo", rowGroup: "Ya",
                            exampleWord: "よる", exampleReading: "yoru", exampleMeaning: "buổi tối",
                            strokeCount: 2, mnemonicTip: "Chữ よ có nét thắt tròn như mặt trăng tròn trồi lên vào buổi tối.")
        ]),
        ("Hàng Ra (ら行)", [
            NHKJapaneseItem(id: "ra", hiragana: "ら", katakana: "ラ", romaji: "ra", rowGroup: "Ra",
                            exampleWord: "らくだ", exampleReading: "rakuda", exampleMeaning: "con lạc đà",
                            strokeCount: 2, mnemonicTip: "Chữ ら có nét phẩy trên đầu và bướu tròn như lưng lạc đà."),
            NHKJapaneseItem(id: "ri", hiragana: "り", katakana: "リ", romaji: "ri", rowGroup: "Ra",
                            exampleWord: "りんご", exampleReading: "ringo", exampleMeaning: "quả táo",
                            strokeCount: 2, mnemonicTip: "Chữ り gồm 2 nét cong nhẹ dài như dải ruy băng buộc quả táo đỏ."),
            NHKJapaneseItem(id: "ru", hiragana: "る", katakana: "ル", romaji: "ru", rowGroup: "Ra",
                            exampleWord: "るす", exampleReading: "rusu", exampleMeaning: "vắng nhà",
                            strokeCount: 1, mnemonicTip: "Chữ る có vòng tròn thắt xoắn ở đuôi như chiếc chìa khoá để lại khi vắng nhà."),
            NHKJapaneseItem(id: "re", hiragana: "れ", katakana: "レ", romaji: "re", rowGroup: "Ra",
                            exampleWord: "れい", exampleReading: "rei", exampleMeaning: "số không / ví dụ",
                            strokeCount: 2, mnemonicTip: "Chữ れ có nét hất ngoắc ra ngoài như một người lịch sự cúi chào lễ phép."),
            NHKJapaneseItem(id: "ro", hiragana: "ろ", katakana: "ロ", romaji: "ro", rowGroup: "Ra",
                            exampleWord: "ろく", exampleReading: "roku", exampleMeaning: "số sáu",
                            strokeCount: 1, mnemonicTip: "Chữ ろ giống chữ る nhưng đuôi để mở không thắt vòng tròn.")
        ]),
        ("Hàng Wa & Âm N (わ行・ん)", [
            NHKJapaneseItem(id: "wa", hiragana: "わ", katakana: "ワ", romaji: "wa", rowGroup: "Wa",
                            exampleWord: "わに", exampleReading: "wani", exampleMeaning: "con cá sấu",
                            strokeCount: 2, mnemonicTip: "Chữ わ có thân đứng và vòng bụng to tròn như chiếc hồ bơi của cá sấu."),
            NHKJapaneseItem(id: "wo", hiragana: "を", katakana: "ヲ", romaji: "wo (o)", rowGroup: "Wa",
                            exampleWord: "パンをたべる", exampleReading: "pan o taberu", exampleMeaning: "ăn bánh mì (trợ từ)",
                            strokeCount: 3, mnemonicTip: "Chữ を chủ yếu dùng làm trợ từ ngữ pháp tân ngữ trong tiếng Nhật."),
            NHKJapaneseItem(id: "n", hiragana: "ん", katakana: "ン", romaji: "n", rowGroup: "N",
                            exampleWord: "ほん", exampleReading: "hon", exampleMeaning: "quyển sách",
                            strokeCount: 1, mnemonicTip: "Chữ ん chỉ 1 nét lượn sóng nhẹ nhàng, là âm mũi duy nhất đứng một mình.")
        ])
    ]

    // MARK: - Âm đục (Dakuon) & Bán đục (Handakuon)
    static let dakuonRows: [(name: String, items: [NHKJapaneseItem])] = [
        ("Hàng Ga (が行)", [
            NHKJapaneseItem(id: "ga", hiragana: "が", katakana: "ガ", romaji: "ga", rowGroup: "Ga", exampleWord: "がくせい", exampleReading: "gakusei", exampleMeaning: "học sinh", strokeCount: 5, mnemonicTip: "Âm đục thêm dấu ten-ten (゛) vào か"),
            NHKJapaneseItem(id: "gi", hiragana: "ぎ", katakana: "ギ", romaji: "gi", rowGroup: "Ga", exampleWord: "ぎんこう", exampleReading: "ginkou", exampleMeaning: "ngân hàng", strokeCount: 6, mnemonicTip: "Âm đục thêm dấu ten-ten vào き"),
            NHKJapaneseItem(id: "gu", hiragana: "ぐ", katakana: "グ", romaji: "gu", rowGroup: "Ga", exampleWord: "ぐんじん", exampleReading: "gunjin", exampleMeaning: "quân nhân", strokeCount: 3, mnemonicTip: "Âm đục thêm dấu ten-ten vào く"),
            NHKJapaneseItem(id: "ge", hiragana: "げ", katakana: "ゲ", romaji: "ge", rowGroup: "Ga", exampleWord: "げんき", exampleReading: "genki", exampleMeaning: "khoẻ mạnh", strokeCount: 5, mnemonicTip: "Âm đục thêm dấu ten-ten vào け"),
            NHKJapaneseItem(id: "go", hiragana: "ご", katakana: "ゴ", romaji: "go", rowGroup: "Ga", exampleWord: "ごはん", exampleReading: "gohan", exampleMeaning: "cơm, bữa ăn", strokeCount: 4, mnemonicTip: "Âm đục thêm dấu ten-ten vào こ")
        ]),
        ("Hàng Za (ざ行)", [
            NHKJapaneseItem(id: "za", hiragana: "ざ", katakana: "ザ", romaji: "za", rowGroup: "Za", exampleWord: "ざっし", exampleReading: "zasshi", exampleMeaning: "tạp chí", strokeCount: 5, mnemonicTip: "Âm đục của さ"),
            NHKJapaneseItem(id: "ji", hiragana: "じ", katakana: "ジ", romaji: "ji", rowGroup: "Za", exampleWord: "じかん", exampleReading: "jikan", exampleMeaning: "thời gian", strokeCount: 3, mnemonicTip: "Âm đục của し, đọc là ji"),
            NHKJapaneseItem(id: "zu", hiragana: "ず", katakana: "ズ", romaji: "zu", rowGroup: "Za", exampleWord: "みず", exampleReading: "mizu", exampleMeaning: "nước uống", strokeCount: 4, mnemonicTip: "Âm đục của す"),
            NHKJapaneseItem(id: "ze", hiragana: "ぜ", katakana: "ゼ", romaji: "ze", rowGroup: "Za", exampleWord: "ぜんぶ", exampleReading: "zenbu", exampleMeaning: "tất cả", strokeCount: 5, mnemonicTip: "Âm đục của せ"),
            NHKJapaneseItem(id: "zo", hiragana: "ぞ", katakana: "ゾ", romaji: "zo", rowGroup: "Za", exampleWord: "ぞう", exampleReading: "zou", exampleMeaning: "con voi", strokeCount: 3, mnemonicTip: "Âm đục của そ")
        ]),
        ("Hàng Da (だ行)", [
            NHKJapaneseItem(id: "da", hiragana: "だ", katakana: "ダ", romaji: "da", rowGroup: "Da", exampleWord: "だいがく", exampleReading: "daigaku", exampleMeaning: "trường đại học", strokeCount: 6, mnemonicTip: "Âm đục của た"),
            NHKJapaneseItem(id: "dji", hiragana: "ぢ", katakana: "ヂ", romaji: "ji (di)", rowGroup: "Da", exampleWord: "はなぢ", exampleReading: "hanaji", exampleMeaning: "chảy máu cam", strokeCount: 4, mnemonicTip: "Âm đục của ち"),
            NHKJapaneseItem(id: "dzu", hiragana: "づ", katakana: "ヅ", romaji: "zu (du)", rowGroup: "Da", exampleWord: "つづく", exampleReading: "tsuzuku", exampleMeaning: "tiếp tục", strokeCount: 3, mnemonicTip: "Âm đục của つ"),
            NHKJapaneseItem(id: "de", hiragana: "で", katakana: "デ", romaji: "de", rowGroup: "Da", exampleWord: "でんしゃ", exampleReading: "densha", exampleMeaning: "tàu điện", strokeCount: 3, mnemonicTip: "Âm đục của て"),
            NHKJapaneseItem(id: "do", hiragana: "ど", katakana: "ド", romaji: "do", rowGroup: "Da", exampleWord: "どこ", exampleReading: "doko", exampleMeaning: "ở đâu", strokeCount: 4, mnemonicTip: "Âm đục của と")
        ]),
        ("Hàng Ba (ば行) & Pa (ぱ行)", [
            NHKJapaneseItem(id: "ba", hiragana: "ば", katakana: "バ", romaji: "ba", rowGroup: "Ba", exampleWord: "バス", exampleReading: "basu", exampleMeaning: "xe buýt", strokeCount: 5, mnemonicTip: "Âm đục có dấu ten-ten (゛)"),
            NHKJapaneseItem(id: "bi", hiragana: "び", katakana: "ビ", romaji: "bi", rowGroup: "Ba", exampleWord: "ビール", exampleReading: "biiru", exampleMeaning: "bia", strokeCount: 3, mnemonicTip: "Âm đục của ひ"),
            NHKJapaneseItem(id: "bu", hiragana: "ぶ", katakana: "ブ", romaji: "bu", rowGroup: "Ba", exampleWord: "ぶた", exampleReading: "buta", exampleMeaning: "con lợn", strokeCount: 6, mnemonicTip: "Âm đục của ふ"),
            NHKJapaneseItem(id: "be", hiragana: "べ", katakana: "ベ", romaji: "be", rowGroup: "Ba", exampleWord: "べんきょう", exampleReading: "benkyou", exampleMeaning: "học tập", strokeCount: 3, mnemonicTip: "Âm đục của へ"),
            NHKJapaneseItem(id: "bo", hiragana: "ぼ", katakana: "ボ", romaji: "bo", rowGroup: "Ba", exampleWord: "ぼうし", exampleReading: "boushi", exampleMeaning: "cái mũ", strokeCount: 6, mnemonicTip: "Âm đục của ほ"),
            NHKJapaneseItem(id: "pa", hiragana: "ぱ", katakana: "パ", romaji: "pa", rowGroup: "Pa", exampleWord: "パン", exampleReading: "pan", exampleMeaning: "bánh mì", strokeCount: 4, mnemonicTip: "Âm bán đục có dấu maru tròn (゜)"),
            NHKJapaneseItem(id: "pi", hiragana: "ぴ", katakana: "ピ", romaji: "pi", rowGroup: "Pa", exampleWord: "ピアノ", exampleReading: "piano", exampleMeaning: "đàn piano", strokeCount: 2, mnemonicTip: "Âm bán đục của ひ"),
            NHKJapaneseItem(id: "pu", hiragana: "ぷ", katakana: "プ", romaji: "pu", rowGroup: "Pa", exampleWord: "プール", exampleReading: "puuru", exampleMeaning: "hồ bơi", strokeCount: 5, mnemonicTip: "Âm bán đục của ふ"),
            NHKJapaneseItem(id: "pe", hiragana: "ぺ", katakana: "ペ", romaji: "pe", rowGroup: "Pa", exampleWord: "ペン", exampleReading: "pen", exampleMeaning: "bút mực", strokeCount: 2, mnemonicTip: "Âm bán đục của へ"),
            NHKJapaneseItem(id: "po", hiragana: "ぽ", katakana: "ポ", romaji: "po", rowGroup: "Pa", exampleWord: "ポスト", exampleReading: "posuto", exampleMeaning: "hộp thư", strokeCount: 5, mnemonicTip: "Âm bán đục của ほ")
        ])
    ]

    // MARK: - Âm ghép (Yōon)
    static let yoonRows: [(name: String, items: [NHKJapaneseItem])] = [
        ("Âm ghép cơ bản", [
            NHKJapaneseItem(id: "kya", hiragana: "きゃ", katakana: "キャ", romaji: "kya", rowGroup: "Yoon", exampleWord: "きゃく", exampleReading: "kyaku", exampleMeaning: "vị khách", strokeCount: 7, mnemonicTip: "Ghép き với chữ ゃ nhỏ"),
            NHKJapaneseItem(id: "kyu", hiragana: "きゅ", katakana: "キュ", romaji: "kyu", rowGroup: "Yoon", exampleWord: "きゅうり", exampleReading: "kyuuri", exampleMeaning: "dưa chuột", strokeCount: 6, mnemonicTip: "Ghép き với chữ ゅ nhỏ"),
            NHKJapaneseItem(id: "kyo", hiragana: "きょ", katakana: "キョ", romaji: "kyo", rowGroup: "Yoon", exampleWord: "きょう", exampleReading: "kyou", exampleMeaning: "hôm nay", strokeCount: 6, mnemonicTip: "Ghép き với chữ ょ nhỏ"),
            NHKJapaneseItem(id: "sha", hiragana: "しゃ", katakana: "シャ", romaji: "sha", rowGroup: "Yoon", exampleWord: "しゃしん", exampleReading: "shashin", exampleMeaning: "bức ảnh", strokeCount: 4, mnemonicTip: "Ghép し với chữ ゃ nhỏ"),
            NHKJapaneseItem(id: "shu", hiragana: "しゅ", katakana: "シュ", romaji: "shu", rowGroup: "Yoon", exampleWord: "しゅくだい", exampleReading: "shukudai", exampleMeaning: "bài tập về nhà", strokeCount: 3, mnemonicTip: "Ghép し với chữ ゅ nhỏ"),
            NHKJapaneseItem(id: "sho", hiragana: "しょ", katakana: "ショ", romaji: "sho", rowGroup: "Yoon", exampleWord: "しょくどう", exampleReading: "shokudou", exampleMeaning: "nhà ăn", strokeCount: 3, mnemonicTip: "Ghép し với chữ ょ nhỏ"),
            NHKJapaneseItem(id: "cha", hiragana: "ちゃ", katakana: "チャ", romaji: "cha", rowGroup: "Yoon", exampleWord: "おちゃ", exampleReading: "ocha", exampleMeaning: "trà xanh", strokeCount: 5, mnemonicTip: "Ghép ち với chữ ゃ nhỏ"),
            NHKJapaneseItem(id: "chu", hiragana: "ちゅ", katakana: "チュ", romaji: "chu", rowGroup: "Yoon", exampleWord: "ちゅうしゃ", exampleReading: "chuusha", exampleMeaning: "tiêm thuốc", strokeCount: 4, mnemonicTip: "Ghép ち với chữ ゅ nhỏ"),
            NHKJapaneseItem(id: "cho", hiragana: "ちょ", katakana: "チョ", romaji: "cho", rowGroup: "Yoon", exampleWord: "ちょっと", exampleReading: "chotto", exampleMeaning: "một chút", strokeCount: 4, mnemonicTip: "Ghép ち với chữ ょ nhỏ"),
            NHKJapaneseItem(id: "nya", hiragana: "にゃ", katakana: "ニャ", romaji: "nya", rowGroup: "Yoon", exampleWord: "にゃんこ", exampleReading: "nyanko", exampleMeaning: "mèo con", strokeCount: 6, mnemonicTip: "Ghép に với chữ ゃ nhỏ"),
            NHKJapaneseItem(id: "ryo", hiragana: "りょ", katakana: "リョ", romaji: "ryo", rowGroup: "Yoon", exampleWord: "りょこう", exampleReading: "ryokou", exampleMeaning: "du lịch", strokeCount: 4, mnemonicTip: "Ghép り với chữ ょ nhỏ")
        ])
    ]

    static var allGojuonItems: [NHKJapaneseItem] {
        gojuonRows.flatMap { $0.items }
    }
}
