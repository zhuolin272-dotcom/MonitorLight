using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace MonitorLight;

internal sealed class MonitorSettings
{
    private readonly string directory;

    internal MonitorSettings(string directory) => this.directory = directory;

    private string BaselinePath(string id)
    {
        string hex = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(id.ToUpperInvariant())));
        return Path.Combine(directory, $"{hex}.json");
    }

    internal Rgb? ReadBaseline(string id)
    {
        try
        {
            var baseline = JsonSerializer.Deserialize<Rgb>(File.ReadAllText(BaselinePath(id)));
            if (baseline is not { IsValid: true })
                throw new JsonException();
            return baseline;
        }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
        catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException)
        {
            throw new InvalidOperationException("无法读取已保存的原色，冷暖已停用。", error);
        }
    }

    internal void SaveBaseline(string id, Rgb baseline)
    {
        string path = BaselinePath(id);
        string temp = $"{path}.{Guid.NewGuid():N}.tmp";
        try
        {
            Directory.CreateDirectory(directory);
            File.WriteAllText(temp, JsonSerializer.Serialize(baseline));
            File.Move(temp, path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new InvalidOperationException("无法保存原色，冷暖未写入显示器。", error);
        }
        finally
        {
            try { File.Delete(temp); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
        }
    }

    internal string? ReadSelection()
    {
        try { return File.ReadAllText(Path.Combine(directory, "selection.txt")); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return null; }
    }

    internal void SaveSelection(string id)
    {
        try
        {
            Directory.CreateDirectory(directory);
            File.WriteAllText(Path.Combine(directory, "selection.txt"), id);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }
}
