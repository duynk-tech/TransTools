using System.IO;
using System.Text.Json;
using Microsoft.ML.Tokenizers;
namespace TransTools.Services.Translation;
public sealed class MarianTokenizer
{
    private readonly SentencePieceTokenizer _source;
    private readonly Dictionary<string, long> _vocabulary;
    private readonly Dictionary<long, string> _pieces;
    private readonly string? _languageToken;
    public MarianTokenizer(string folder, string? languageToken = null)
    {
        using var stream = File.OpenRead(Path.Combine(folder, "source.spm"));
        _source = SentencePieceTokenizer.Create(stream, false, false);
        _vocabulary = JsonSerializer.Deserialize<Dictionary<string, long>>(File.ReadAllText(Path.Combine(folder, "vocab.json"))) ?? throw new InvalidDataException("Thiếu từ vựng mô hình.");
        _pieces = _vocabulary.ToDictionary(pair => pair.Value, pair => pair.Key);
        _languageToken = languageToken;
        if (!_vocabulary.ContainsKey("</s>") || !_vocabulary.ContainsKey("<unk>") || (languageToken != null && !_vocabulary.ContainsKey(languageToken))) throw new InvalidDataException("Từ vựng không khớp mô hình.");
    }
    public long[] Encode(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) throw new ArgumentException("Nhập nội dung cần dịch.");
        var ids = new List<long>();
        if (_languageToken != null) ids.Add(_vocabulary[_languageToken]);
        foreach (var piece in _source.EncodeToTokens(text, out _)) ids.Add(_vocabulary.GetValueOrDefault(piece.Value, _vocabulary["<unk>"]));
        ids.Add(_vocabulary["</s>"]);
        if (ids.Count > 512) throw new ArgumentException("Đoạn văn vượt giới hạn mô hình.");
        return ids.ToArray();
    }
    public string Decode(IEnumerable<long> ids)
    {
        var pieces = new List<string>();
        foreach (var id in ids) {
            if (!_pieces.TryGetValue(id, out var piece)) throw new InvalidDataException("Token bản dịch không hợp lệ.");
            if (piece is "</s>" or "<pad>" || piece == _languageToken) continue;
            if (piece == "<unk>" || piece.StartsWith("<0x", StringComparison.Ordinal)) throw new InvalidDataException("Chưa giải mã đủ bản dịch.");
            pieces.Add(piece);
        }
        return string.Concat(pieces).Replace('▁', ' ').Trim();
    }
}
