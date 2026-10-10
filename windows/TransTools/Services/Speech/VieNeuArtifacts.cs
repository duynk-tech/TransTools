// Native implementation of the pinned Apache-2.0 VieNeu byte-BPE/SEA-G2P contract.
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
namespace TransTools.Services.Speech;
public sealed class VieNeuTokenizer
{
    private readonly Dictionary<string, int> _vocab, _ranks = new();
    private readonly string[] _bytes = new string[256];
    private static readonly Regex Pattern = new(@"(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\r\n\p{L}\p{N}]?\p{L}+|\p{N}| ?[^\s\p{L}\p{N}]+[\r\n]*|\s*[\r\n]+|\s+(?!\S)|\s+", RegexOptions.Compiled);
    public VieNeuTokenizer(string path) {
        using var json = JsonDocument.Parse(File.ReadAllText(path)); var model = json.RootElement.GetProperty("model");
        _vocab = model.GetProperty("vocab").EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetInt32());
        var rank = 0; foreach (var pair in model.GetProperty("merges").EnumerateArray()) _ranks[string.Join("\0", pair.EnumerateArray().Select(v => v.GetString()))] = rank++;
        var next = 256;
        for (var b = 0; b < 256; b++) _bytes[b] = char.ConvertFromUtf32((b >= 33 && b <= 126) || (b >= 161 && b <= 172) || b >= 174 ? b : next++);
    }
    public int[] Encode(string text) {
        var ids = new List<int>();
        foreach (Match match in Pattern.Matches(text.Normalize(NormalizationForm.FormC))) {
            var pieces = Encoding.UTF8.GetBytes(match.Value).Select(b => _bytes[b]).ToList();
            while (pieces.Count > 1) {
                int best = -1, rank = int.MaxValue;
                for (var i = 0; i < pieces.Count - 1; i++) if (_ranks.TryGetValue(pieces[i] + "\0" + pieces[i+1], out var value) && value < rank) { best = i; rank = value; }
                if (best < 0) break; pieces[best] += pieces[best+1]; pieces.RemoveAt(best+1);
            }
            ids.AddRange(pieces.Select(p => _vocab.GetValueOrDefault(p, 43)));
        }
        return ids.ToArray();
    }
}
public static class VieNeuArrays
{
    public static Dictionary<string, float[]> Load(string path) {
        using var archive = ZipFile.OpenRead(path); var result = new Dictionary<string, float[]>();
        foreach (var entry in archive.Entries) {
            if (!entry.FullName.EndsWith(".npy") || entry.Length > 100 * 1024 * 1024) throw new InvalidDataException("Mảng VieNeu không hợp lệ.");
            using var reader = new BinaryReader(entry.Open());
            if (!reader.ReadBytes(6).SequenceEqual(new byte[] { 0x93, 78, 85, 77, 80, 89 })) throw new InvalidDataException("Header NPY không hợp lệ.");
            var major = reader.ReadByte(); reader.ReadByte(); var length = major == 1 ? reader.ReadUInt16() : reader.ReadInt32();
            if (length < 1 || length > 65536) throw new InvalidDataException("Header NPY quá lớn.");
            var header = Encoding.ASCII.GetString(reader.ReadBytes(length));
            if (!header.Contains("'<f4'") || !header.Contains("False")) throw new InvalidDataException("VieNeu cần trọng số float32 little-endian.");
            var count = checked((int)((entry.Length - (major == 1 ? 10 : 12) - length) / 4));
            var values = new float[count]; for (var i = 0; i < count; i++) values[i] = reader.ReadSingle();
            result.Add(entry.FullName[..^4], values);
        }
        return result;
    }
}
public sealed class VieNeuPhonemizer : IDisposable
{
    private IntPtr _library, _handle;
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate int Abi();
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr Open([MarshalAs(UnmanagedType.LPUTF8Str)] string path);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void Close(IntPtr handle);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr Convert(IntPtr handle, [MarshalAs(UnmanagedType.LPUTF8Str)] string text, int flags);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate void Free(IntPtr text);
    private readonly Close _close;
    private readonly Convert _convert;
    private readonly Free _free;
    public VieNeuPhonemizer(string library, string dictionary) {
        _library = NativeLibrary.Load(library);
        try {
            T Function<T>(string name) where T : Delegate => Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(_library, name));
            if (Function<Abi>("sea_g2p_abi_version")() != 1) throw new InvalidDataException("SEA-G2P ABI không tương thích.");
            _close = Function<Close>("sea_g2p_close"); _convert = Function<Convert>("sea_g2p_phonemize"); _free = Function<Free>("sea_g2p_string_free");
            _handle = Function<Open>("sea_g2p_open")(dictionary);
            if (_handle == IntPtr.Zero) throw new InvalidDataException("Không mở được từ điển phát âm.");
        } catch { NativeLibrary.Free(_library); _library = IntPtr.Zero; throw; }
    }
    public string Phonemes(string text) {
        ObjectDisposedException.ThrowIf(_handle == IntPtr.Zero, this);
        var value = _convert(_handle, text, 1); if (value == IntPtr.Zero) throw new InvalidDataException("Không chuyển được âm vị.");
        try { return Marshal.PtrToStringUTF8(value) ?? throw new InvalidDataException("Âm vị không hợp lệ."); } finally { _free(value); }
    }
    public void Dispose() { if (_handle != IntPtr.Zero) { _close(_handle); _handle = IntPtr.Zero; } if (_library != IntPtr.Zero) { NativeLibrary.Free(_library); _library = IntPtr.Zero; } }
}
