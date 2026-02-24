using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ralph.BacklogCli;

public static class BacklogStore
{
    private static readonly JsonSerializerOptions SerializerOptions = CreateSerializerOptions();

    public static string ReadRaw(string backlogPath)
    {
        return File.ReadAllText(backlogPath);
    }

    public static BacklogDocument Load(string backlogPath)
    {
        var json = ReadRaw(backlogPath);
        var doc = JsonSerializer.Deserialize<BacklogDocument>(json, SerializerOptions);
        if (doc is null)
        {
            throw new InvalidDataException($"Failed to deserialize backlog file '{backlogPath}'.");
        }

        return doc;
    }

    public static void Save(string backlogPath, BacklogDocument document)
    {
        var dir = Path.GetDirectoryName(backlogPath);
        if (!string.IsNullOrWhiteSpace(dir))
        {
            Directory.CreateDirectory(dir);
        }

        var json = JsonSerializer.Serialize(document, SerializerOptions);
        var tempPath = backlogPath + ".tmp";
        File.WriteAllText(tempPath, json);
        File.Move(tempPath, backlogPath, overwrite: true);
    }

    public static string GetLockFilePath(string backlogPath)
    {
        var dir = Path.GetDirectoryName(backlogPath);
        if (string.IsNullOrWhiteSpace(dir))
        {
            dir = Directory.GetCurrentDirectory();
        }

        return Path.Combine(dir, "backlog.lock");
    }

    private static JsonSerializerOptions CreateSerializerOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = true,
            PropertyNameCaseInsensitive = false,
            UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
        };

        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false));
        return options;
    }
}
