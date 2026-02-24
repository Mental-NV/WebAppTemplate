using System.Text.Json.Serialization;

namespace Ralph.BacklogCli;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class BacklogDocument
{
    public int Version { get; set; }
    public List<BacklogItem> Items { get; set; } = [];
}

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed class BacklogItem
{
    public string Id { get; set; } = "";
    public string Title { get; set; } = "";
    public string Description { get; set; } = "";
    public int Priority { get; set; }
    public List<string> Dependencies { get; set; } = [];

    [JsonConverter(typeof(JsonStringEnumConverter<BacklogStatus>))]
    public BacklogStatus Status { get; set; }

    public DateTimeOffset? StartedAt { get; set; }
    public DateTimeOffset? DoneAt { get; set; }
}

public enum BacklogStatus
{
    New,
    InProgress,
    InReview,
    Done
}

public sealed record ValidationIssue(
    string Code,
    string Message,
    string? ItemId = null,
    string? DependencyId = null,
    string? Field = null);
