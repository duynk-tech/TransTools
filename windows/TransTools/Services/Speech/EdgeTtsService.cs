using System;
using System.Collections.Generic;
using System.IO;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using NAudio.Wave;

namespace TransTools.Services.Speech;

public class EdgeTtsVoice
{
    public string ShortName { get; set; } = string.Empty;
    public string DisplayName { get; set; } = string.Empty;
    public string Locale { get; set; } = string.Empty;
    public string Gender { get; set; } = string.Empty;
}

public class EdgeTtsService
{
    private const string WssUrl = "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4";

    public static readonly List<EdgeTtsVoice> DefaultVoices = new()
    {
        new() { ShortName = "vi-VN-HoaiMyNeural", DisplayName = "Hoài My (Nữ - Miền Nam)", Locale = "vi-VN", Gender = "Female" },
        new() { ShortName = "vi-VN-NamMinhNeural", DisplayName = "Nam Minh (Nam - Miền Bắc)", Locale = "vi-VN", Gender = "Male" },
        new() { ShortName = "en-US-JennyNeural", DisplayName = "Jenny (English US)", Locale = "en-US", Gender = "Female" },
        new() { ShortName = "en-US-GuyNeural", DisplayName = "Guy (English US)", Locale = "en-US", Gender = "Male" },
        new() { ShortName = "ja-JP-NanamiNeural", DisplayName = "Nanami (Japanese)", Locale = "ja-JP", Gender = "Female" },
        new() { ShortName = "zh-CN-XiaoxiaoNeural", DisplayName = "Xiaoxiao (Chinese)", Locale = "zh-CN", Gender = "Female" },
        new() { ShortName = "ko-KR-SunHiNeural", DisplayName = "Sun-Hi (Korean)", Locale = "ko-KR", Gender = "Female" }
    };

    public static string VoiceForLanguage(string language)
    {
        var code = language.ToLowerInvariant();
        if (code.StartsWith("vi") || code.Contains("việt")) return "vi-VN-HoaiMyNeural";
        if (code.StartsWith("ja") || code.Contains("nhật")) return "ja-JP-NanamiNeural";
        if (code.StartsWith("zh") || code.Contains("trung")) return "zh-CN-XiaoxiaoNeural";
        if (code.StartsWith("ko") || code.Contains("hàn")) return "ko-KR-SunHiNeural";
        return "en-US-JennyNeural";
    }

    public async Task<byte[]> SynthesizeAsync(string text, string voiceName = "vi-VN-HoaiMyNeural", double rate = 1.0, double pitch = 1.0, CancellationToken cancellationToken = default)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(45));
        var token = timeout.Token;
        using var client = new ClientWebSocket();
        client.Options.SetRequestHeader("Pragma", "no-cache");
        client.Options.SetRequestHeader("Cache-Control", "no-cache");
        client.Options.SetRequestHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0");
        client.Options.SetRequestHeader("Origin", "chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold");

        await client.ConnectAsync(new Uri(WssUrl), token);

        var requestId = Guid.NewGuid().ToString("N");
        var timestamp = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ");

        // Step 1: Send configuration
        var configMessage = $"X-Timestamp:{timestamp}\r\nContent-Type:application/json; charset=utf-8\r\nPath:speech.config\r\n\r\n" +
            "{\"context\":{\"synthesis\":{\"audio\":{\"metadataoptions\":{\"sentenceBoundaryEnabled\":\"false\",\"wordBoundaryEnabled\":\"false\"},\"outputFormat\":\"audio-24khz-48kbitrate-mono-mp3\"}}}}";
        await client.SendAsync(Encoding.UTF8.GetBytes(configMessage), WebSocketMessageType.Text, true, token);

        // Step 2: Send SSML synthesis request
        var rateStr = rate >= 1.0 ? $"+{Math.Round((rate - 1.0) * 100)}%" : $"-{Math.Round((1.0 - rate) * 100)}%";
        var ssml = $"<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>" +
                   $"<voice name='{voiceName}'><prosody rate='{rateStr}'>{System.Security.SecurityElement.Escape(text)}</prosody></voice></speak>";

        var ssmlMessage = $"X-RequestId:{requestId}\r\nContent-Type:application/ssml+xml\r\nX-Timestamp:{timestamp}\r\nPath:ssml\r\n\r\n{ssml}";
        await client.SendAsync(Encoding.UTF8.GetBytes(ssmlMessage), WebSocketMessageType.Text, true, token);

        // Step 3: Receive audio chunks
        using var audioStream = new MemoryStream();
        var buffer = new byte[8192];

        while (client.State == WebSocketState.Open)
        {
            using var message = new MemoryStream();
            WebSocketReceiveResult result;
            do
            {
                result = await client.ReceiveAsync(new ArraySegment<byte>(buffer), token);
                message.Write(buffer, 0, result.Count);
                if (message.Length > 16 * 1024 * 1024) throw new InvalidDataException("TTS message too large.");
            } while (!result.EndOfMessage && result.MessageType != WebSocketMessageType.Close);
            var payload = message.ToArray();
            if (result.MessageType == WebSocketMessageType.Close) break;

            if (result.MessageType == WebSocketMessageType.Binary && payload.Length > 2)
            {
                // Edge TTS binary format: 2-byte header length (big-endian), then header string, then binary audio
                int headerLength = (payload[0] << 8) | payload[1];
                if (payload.Length > headerLength + 2)
                {
                    int audioOffset = headerLength + 2;
                    int audioCount = payload.Length - audioOffset;
                    audioStream.Write(payload, audioOffset, audioCount);
                }
            }
            else if (result.MessageType == WebSocketMessageType.Text)
            {
                var textMsg = Encoding.UTF8.GetString(payload);
                if (textMsg.Contains("Path:turn.end"))
                {
                    break;
                }
            }
        }

        if (client.State == WebSocketState.Open) await client.CloseAsync(WebSocketCloseStatus.NormalClosure, "Complete", token);
        return audioStream.ToArray();
    }

    public async Task SpeakAsync(string text, string voiceName = "vi-VN-HoaiMyNeural", double rate = 1.0)
    {
        var mp3Bytes = await SynthesizeAsync(text, voiceName, rate);
        if (mp3Bytes.Length == 0) return;

        using var ms = new MemoryStream(mp3Bytes);
        using var reader = new Mp3FileReader(ms);
        using var waveOut = new WaveOutEvent();
        waveOut.Init(reader);
        waveOut.Play();
        while (waveOut.PlaybackState == PlaybackState.Playing)
        {
            await Task.Delay(100);
        }
    }
}
