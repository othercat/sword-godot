// SPDX-License-Identifier: MIT
// Development-only exporter. The player uses data, not a .NET process or DLL.
using System.Buffers.Binary;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Runtime.Loader;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

const uint Invalid = uint.MaxValue;
const uint Lead = uint.MaxValue - 1;
const string ProviderSha = "f1d8adcd3569623c65ebc17497772f22bec9b6781c8b10e690637eeb44f91543";
if (args.Length != 6 || args[0] != "--package" || args[2] != "--gui-report" || args[4] != "--output")
    throw new ArgumentException("--package <CodePages 8.0.0 directory> --gui-report <source-window report> --output <fresh directory>");
var packageRoot = Path.GetFullPath(args[1]);
var guiPath = Path.GetFullPath(args[3]);
var output = Path.GetFullPath(args[5]);
if (Directory.Exists(output) || File.Exists(output)) throw new IOException("Use a fresh output directory.");
var dll = Path.Combine(packageRoot, "lib", "net8.0", "System.Text.Encoding.CodePages.dll");
if (Hash(File.ReadAllBytes(dll)) != ProviderSha) throw new InvalidDataException("Pinned provider assembly mismatch.");
var load = new AssemblyLoadContext("pinned-codepages", isCollectible: true);
var assembly = load.LoadFromAssemblyPath(dll);
var provider = (EncodingProvider)assembly.GetType("System.Text.CodePagesEncodingProvider", true)!
    .GetProperty("Instance", BindingFlags.Public | BindingFlags.Static)!.GetValue(null)!;
Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
Directory.CreateDirectory(output);
var tables = Path.Combine(output, "encodings"); Directory.CreateDirectory(tables);
var oracles = Path.Combine(output, "oracle"); Directory.CreateDirectory(oracles);
var codecRows = new List<object>();
var liveEncodings = new Dictionary<string, Encoding>();
foreach (var (name, cp) in new[] { ("gbk", 936), ("big5", 950) })
{
    var pinned = provider.GetEncoding(cp, EncoderFallback.ExceptionFallback, DecoderFallback.ExceptionFallback)!;
    var current = Encoding.GetEncoding(cp, EncoderFallback.ExceptionFallback, DecoderFallback.ExceptionFallback);
    liveEncodings.Add(name, current);
    var single = Enumerable.Repeat(Invalid, 256).ToArray();
    var pair = Enumerable.Repeat(Invalid, 65536).ToArray();
    for (var first = 0; first < 256; first++)
    {
        var one = Scalars(pinned, [(byte)first]);
        if (one.Length == 1) single[first] = one[0];
        if (single[first] != Invalid) continue;
        for (var second = 0; second < 256; second++)
        {
            var two = Scalars(pinned, [(byte)first, (byte)second]);
            if (two.Length != 1) continue;
            pair[first * 256 + second] = two[0]; single[first] = Lead;
        }
    }
    using var data = new MemoryStream();
    using (var writer = new BinaryWriter(data, Encoding.UTF8, true))
    {
        writer.Write("PWCP"u8); writer.Write(1u); writer.Write(cp);
        foreach (var item in single.Concat(pair)) writer.Write(item);
    }
    var filename = $"cp{cp}.bin"; File.WriteAllBytes(Path.Combine(tables, filename), data.ToArray());
    using var oracle = new MemoryStream();
    using (var writer = new BinaryWriter(oracle, Encoding.UTF8, true))
    {
        // Independent oracle calls the CURRENT framework on each WHOLE sequence.
        // Include two singles and invalid trail cases, not just mapping entries.
        for (var index = 0; index < 256 + 65536; index++)
        {
            byte[] input = index < 256 ? [(byte)index] : [(byte)((index - 256) >> 8), (byte)(index - 256)];
            var a = Result(pinned, input); var b = Result(current, input);
            if (a != b) throw new InvalidDataException($"Provider drift: CP{cp}, {Convert.ToHexString(input)}");
            writer.Write(b.ErrorIndex is not null ? Invalid : (uint)b.Text!.EnumerateRunes().Count());
            var runes = b.Text?.EnumerateRunes().Select(r => (uint)r.Value).ToArray() ?? [];
            if (runes.Length > 2) throw new InvalidDataException("Unexpected expansion.");
            writer.Write(b.ErrorIndex is not null ? (uint)b.ErrorIndex : runes.ElementAtOrDefault(0));
            writer.Write(runes.ElementAtOrDefault(1));
        }
    }
    File.WriteAllBytes(Path.Combine(oracles, filename), oracle.ToArray());
    codecRows.Add(new { encoding = name, code_page = cp, file = filename, size_bytes = data.Length,
        sha256 = Hash(data.ToArray()), single_count = single.Count(v => v <= 0x10ffff),
        lead_count = single.Count(v => v == Lead), pair_count = pair.Count(v => v != Invalid),
        oracle_cases = 65792, oracle_sha256 = Hash(oracle.ToArray()) });
}
foreach (var file in new[] { "LICENSE.TXT", "THIRD-PARTY-NOTICES.TXT" })
    File.Copy(Path.Combine(packageRoot, file), Path.Combine(tables, "DOTNET-" + file));
Write(Path.Combine(tables, "manifest.json"), new { profile = "pal98.codepages-dotnet8.v1", tables = codecRows,
    provider = new { package = "System.Text.Encoding.CodePages", version = "8.0.0", sha256 = ProviderSha,
        repository = "https://github.com/dotnet/runtime", commit = "5535e31a712343a63f5d7d796cd874e563e5ac14",
        license_sha256 = Hash(File.ReadAllBytes(Path.Combine(packageRoot, "LICENSE.TXT"))),
        notices_sha256 = Hash(File.ReadAllBytes(Path.Combine(packageRoot, "THIRD-PARTY-NOTICES.TXT"))) } });

using var gui = JsonDocument.Parse(File.ReadAllBytes(guiPath));
var root = gui.RootElement;
if (!root.GetProperty("success").GetBoolean()) throw new InvalidDataException("Source-window report failed.");
var contentPath = root.GetProperty("package").GetString()!;
var descriptor = root.GetProperty("descriptor");
var encodingName = descriptor.GetProperty("text_encoding").GetString()!;
var codec = liveEncodings[encodingName];
using var archive = ZipFile.OpenRead(contentPath);
var raw = new Dictionary<string, byte[]>();
foreach (var role in new[] { "data", "sss", "words", "messages" })
{
    var entry = descriptor.GetProperty("files").GetProperty(role);
    using var stream = archive.GetEntry(entry.GetProperty("path").GetString()!)!.Open();
    using var memory = new MemoryStream(); stream.CopyTo(memory); var bytes = memory.ToArray();
    if (Hash(bytes) != entry.GetProperty("sha256").GetString()) throw new InvalidDataException("Source hash mismatch.");
    raw.Add(role, bytes);
}
var rows = new List<object>();
for (var offset = 0; offset < raw["words"].Length; offset += 10)
    AddSource("words", offset / 10, offset, raw["words"].AsSpan(offset, 10).ToArray());
var sss = raw["sss"]; var directoryStart = checked((int)U32(sss, 12)); var directoryEnd = checked((int)U32(sss, 16));
for (var at = directoryStart; at + 4 < directoryEnd; at += 4)
{
    var begin = checked((int)U32(sss, at)); var end = checked((int)U32(sss, at + 4));
    AddSource("messages", (at - directoryStart) / 4, begin, raw["messages"].AsSpan(begin, end - begin).ToArray());
}
var tail = checked((int)U32(sss, directoryEnd - 4)); AddSource("tail", 0, tail, raw["messages"].AsSpan(tail).ToArray());
Write(Path.Combine(output, "reference.json"), new { success = true,
    current_framework = RuntimeInformation.FrameworkDescription,
    current_provider_sha256 = Hash(File.ReadAllBytes(typeof(CodePagesEncodingProvider).Assembly.Location)),
    current_provider_version = typeof(CodePagesEncodingProvider).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion,
    operating_system = RuntimeInformation.OSDescription,
    gui_sha256 = Hash(File.ReadAllBytes(guiPath)), package_sha256 = Hash(File.ReadAllBytes(contentPath)),
    source_fingerprint = descriptor.GetProperty("fingerprint").GetString(), encoding = encodingName,
    tables = codecRows, source_rows = rows, original_gameplay = false, human_acceptance = false });
Console.WriteLine($"Exported 2 tables; 131584 whole-sequence provider comparisons; {rows.Count} source records.");

void AddSource(string role, int index, int offset, byte[] bytes)
{
    var result = Result(codec, bytes);
    rows.Add(new { role, index, byte_offset = offset, size_bytes = bytes.Length, bytes_sha256 = Hash(bytes),
        success = result.ErrorIndex is null, error_offset = result.ErrorIndex,
        utf8_sha256 = result.Text is null ? null : Hash(Encoding.UTF8.GetBytes(result.Text)),
        codepoints = result.Text?.EnumerateRunes().Count() });
}
static uint U32(byte[] bytes, int offset) => BinaryPrimitives.ReadUInt32LittleEndian(bytes.AsSpan(offset, 4));
static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
static void Write(string path, object value) => File.WriteAllText(path, JsonSerializer.Serialize(value,
    new JsonSerializerOptions { WriteIndented = true }) + "\n", new UTF8Encoding(false));
static (string? Text, int? ErrorIndex) Result(Encoding encoding, byte[] bytes)
{
    try { return (encoding.GetString(bytes), null); }
    catch (DecoderFallbackException error) { return (null, error.Index); }
}
static uint[] Scalars(Encoding encoding, byte[] bytes)
{
    var result = Result(encoding, bytes);
    return result.Text?.EnumerateRunes().Select(r => (uint)r.Value).ToArray() ?? [];
}
