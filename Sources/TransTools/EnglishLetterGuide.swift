import Foundation

/// Letter names, distinct from the sounds represented in example words.
struct EnglishLetterGuide {
    static let symbols = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    static let names = ["ay", "bee", "cee", "dee", "ee", "ef", "gee", "aitch", "eye", "jay", "kay", "el", "em", "en", "oh", "pee", "cue", "ar", "ess", "tee", "you", "vee", "double u", "ex", "why", "zee"]
    static let usIPA = ["eɪ", "biː", "siː", "diː", "iː", "ef", "dʒiː", "eɪtʃ", "aɪ", "dʒeɪ", "keɪ", "el", "em", "en", "oʊ", "piː", "kjuː", "ɑːr", "es", "tiː", "juː", "viː", "ˈdʌbəljuː", "eks", "waɪ", "ziː"]
    static func ipa(_ index: Int, british: Bool) -> String {
        guard usIPA.indices.contains(index) else { return "" }
        if british {
            if index == 14 { return "əʊ" }
            if index == 17 { return "ɑː" }
            if index == 25 { return "zed" }
        }
        return usIPA[index]
    }
    static func name(_ index: Int, british: Bool) -> String {
        guard names.indices.contains(index) else { return "" }
        return index == 25 && british ? "zed" : names[index]
    }
    static func note(_ index: Int) -> String {
        switch index {
        case 0: return "Tên A là /eɪ/; trong apple, A biểu thị /æ/. Một chữ có thể biểu thị nhiều âm."
        case 1: return "Tên B là /biː/, giống từ bee: một âm tiết, giữ /iː/ liền mạch; dấu ː chỉ độ dài, không đọc thêm chữ I."
        case 2: return "Tên C là /siː/; cat bắt đầu bằng /k/, city bắt đầu bằng /s/."
        case 4: return "Tên E là /iː/; egg bắt đầu bằng /e/."
        case 6: return "Tên G là /dʒiː/; green bắt đầu bằng /ɡ/, còn giant bằng /dʒ/."
        case 7: return "Tên H là /eɪtʃ/; house bắt đầu bằng /h/. Không thêm âm ‘ơ’ sau âm cuối /tʃ/ của tên chữ."
        case 8: return "Tên I là /aɪ/, giống từ eye. Đây là một âm đôi liền mạch, không tách thành hai tiếng. ice có /aɪ/; sit có /ɪ/."
        case 14: return "Tên O: Anh–Mỹ /oʊ/, Anh–Anh /əʊ/. Âm của O trong từ phụ thuộc từ và giọng."
        case 17: return "Tên R: Anh–Mỹ /ɑːr/, Anh–Anh /ɑː/. Đừng dùng cách đọc tiếng Việt thay cho mẫu nghe."
        case 20: return "Tên U là /juː/; umbrella bắt đầu bằng /ʌ/."
        case 22: return "Tên W là double u; water bắt đầu bằng /w/. Tên chữ và âm trong từ khác nhau."
        case 23: return "Tên X là /eks/; trong box, X biểu thị chuỗi âm /ks/."
        case 24: return "Tên Y là /waɪ/; yellow bắt đầu bằng /j/, my kết thúc bằng /aɪ/."
        case 25: return "Tên Z: Anh–Anh zed /zed/, Anh–Mỹ zee /ziː/. Trong zoo, Z biểu thị /z/."
        default: return "Nghe tên chữ để đánh vần; nghe từ và câu để học âm thực tế. Không thêm nguyên âm sau phụ âm cuối."
        }
    }
}
