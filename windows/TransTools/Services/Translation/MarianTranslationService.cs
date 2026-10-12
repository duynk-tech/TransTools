namespace TransTools.Services.Translation;

// One installed language pair per instance. No network access or automatic provider fallback.
public sealed class MarianTranslationService : IAsyncDisposable
{
    private readonly string _folder;
    private readonly string? _languageToken;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private MarianTokenizer? _tokenizer;
    private MarianTokenDecoder? _decoder;
    private bool _disposed;
    public string SourceLanguage { get; }
    public string TargetLanguage { get; }
    public MarianTranslationService(string folder, string sourceLanguage, string targetLanguage)
    {
        if ((sourceLanguage, targetLanguage) is not ("en", "vi") and not ("vi", "en")) throw new NotSupportedException("Chưa hỗ trợ cặp ngôn ngữ offline này.");
        _folder = folder; SourceLanguage = sourceLanguage; TargetLanguage = targetLanguage;
        _languageToken = targetLanguage == "vi" ? ">>vie<<" : null;
    }
    public async Task<string> TranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try {
            ObjectDisposedException.ThrowIf(_disposed, this);
            cancellationToken.ThrowIfCancellationRequested();
            if (string.IsNullOrWhiteSpace(text)) return "";
            return await Task.Run(() => {
                cancellationToken.ThrowIfCancellationRequested();
                _tokenizer ??= new MarianTokenizer(_folder, _languageToken);
                _decoder ??= new MarianTokenDecoder(_folder);
                var tokens = _tokenizer.Encode(text);
                var output = _decoder.Generate(tokens, cancellationToken);
                cancellationToken.ThrowIfCancellationRequested();
                return _tokenizer.Decode(output);
            }, cancellationToken).ConfigureAwait(false);
        } finally { _gate.Release(); }
    }
    public async ValueTask DisposeAsync()
    {
        await _gate.WaitAsync().ConfigureAwait(false);
        try {
            if (_disposed) return;
            _disposed = true; _decoder?.Dispose(); _decoder = null; _tokenizer = null;
        } finally { _gate.Release(); }
    }
}
