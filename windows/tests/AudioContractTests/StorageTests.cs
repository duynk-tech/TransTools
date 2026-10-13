using System.Security.Cryptography;
using System.Text.Json;
using TransTools.Services.Speech;
using TransTools.Services.Storage;
public static class StorageTests
{
 public static void Run() {
  var root = Path.Combine(Path.GetTempPath(), "trans-tools-test-" + Guid.NewGuid()); Directory.CreateDirectory(root);
  try {
   var file = Path.Combine(root, "model.onnx"); File.WriteAllBytes(file, new byte[] { 1, 2, 3 });
   string Manifest(string path, string hash) => JsonSerializer.Serialize(new { files = new[] { new { path, size = 3, sha256 = hash } } });
   var hash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(file))); ModelVerifier.Verify(root, Manifest("model.onnx", hash), CancellationToken.None);
   Console.WriteLine("PASS: model checksum verified before loading");
   foreach (var manifest in new[] { Manifest("../escape.onnx", hash), Manifest("model.onnx", new string('0', 64)) }) {
    try { ModelVerifier.Verify(root, manifest, CancellationToken.None); throw new Exception("invalid model accepted"); } catch (InvalidDataException) { }
   }
   Console.WriteLine("PASS: corrupt model and path traversal rejected");
   Directory.CreateDirectory(Path.Combine(root, "nested")); File.WriteAllBytes(Path.Combine(root, "nested", "audio.wav"), new byte[11]);
   var entry = StorageInventory.Scan(new StorageEntry("cache", "Cache", "", root, true)); if (entry.Bytes != 14 || entry.Files != 2) throw new Exception("storage accounting");
   var personal = StorageInventory.Scan(new StorageEntry("personal", "Personal", "", root, false)); if (personal.Bytes != 3 || personal.Files != 1) throw new Exception("double-counted nested model");
   Console.WriteLine("PASS: storage categories count nested bytes once");
  } finally { Directory.Delete(root, true); }
 }
}
