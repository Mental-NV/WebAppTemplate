using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Ralph.BacklogCli;

public static partial class JsonSchemaValidator
{
    private static readonly HashSet<string> RootAllowedProperties = ["version", "items"];
    private static readonly HashSet<string> ItemAllowedProperties = ["id", "title", "description", "priority", "dependencies", "status", "startedAt", "doneAt"];
    private static readonly HashSet<string> RequiredItemProperties = ["id", "title", "description", "priority", "dependencies", "status", "startedAt", "doneAt"];
    private static readonly HashSet<string> AllowedStatuses = ["New", "InProgress", "InReview", "Done"];

    public static List<ValidationIssue> Validate(string schemaPath, string backlogPath)
    {
        EnsureSchemaIsReadable(schemaPath);

        if (!File.Exists(backlogPath))
        {
            return
            [
                new ValidationIssue("BacklogFileMissing", $"Backlog file not found: {backlogPath}")
            ];
        }

        using var doc = JsonDocument.Parse(File.ReadAllText(backlogPath));
        var errors = new List<ValidationIssue>();
        ValidateRoot(doc.RootElement, errors);
        return errors;
    }

    private static void EnsureSchemaIsReadable(string schemaPath)
    {
        if (!File.Exists(schemaPath))
        {
            throw new FileNotFoundException($"Backlog schema file not found: {schemaPath}", schemaPath);
        }

        try
        {
            using var _ = JsonDocument.Parse(File.ReadAllText(schemaPath));
        }
        catch (JsonException ex)
        {
            throw new InvalidDataException($"Backlog schema file is not valid JSON: {schemaPath}. {ex.Message}", ex);
        }
    }

    private static void ValidateRoot(JsonElement root, ICollection<ValidationIssue> errors)
    {
        if (root.ValueKind != JsonValueKind.Object)
        {
            errors.Add(new ValidationIssue("SchemaViolation", "Backlog root must be a JSON object."));
            return;
        }

        var props = root.EnumerateObject().ToList();
        foreach (var prop in props)
        {
            if (!RootAllowedProperties.Contains(prop.Name))
            {
                errors.Add(new ValidationIssue(
                    "SchemaViolation",
                    $"Unexpected root property '{prop.Name}'.",
                    Field: prop.Name));
            }
        }

        if (!root.TryGetProperty("version", out var version))
        {
            errors.Add(new ValidationIssue("SchemaViolation", "Missing required root property 'version'.", Field: "version"));
        }
        else if (version.ValueKind != JsonValueKind.Number || !version.TryGetInt32(out var v) || v != 1)
        {
            errors.Add(new ValidationIssue("SchemaViolation", "Property 'version' must be integer 1.", Field: "version"));
        }

        if (!root.TryGetProperty("items", out var items))
        {
            errors.Add(new ValidationIssue("SchemaViolation", "Missing required root property 'items'.", Field: "items"));
            return;
        }

        if (items.ValueKind != JsonValueKind.Array)
        {
            errors.Add(new ValidationIssue("SchemaViolation", "Property 'items' must be an array.", Field: "items"));
            return;
        }

        var index = 0;
        foreach (var item in items.EnumerateArray())
        {
            ValidateItem(item, index, errors);
            index++;
        }
    }

    private static void ValidateItem(JsonElement item, int index, ICollection<ValidationIssue> errors)
    {
        if (item.ValueKind != JsonValueKind.Object)
        {
            errors.Add(new ValidationIssue(
                "SchemaViolation",
                $"Backlog item at index {index} must be an object.",
                Field: $"items[{index}]"));
            return;
        }

        var props = item.EnumerateObject().ToList();
        var propMap = props.ToDictionary(x => x.Name, x => x, StringComparer.Ordinal);

        foreach (var prop in props)
        {
            if (!ItemAllowedProperties.Contains(prop.Name))
            {
                errors.Add(new ValidationIssue(
                    "SchemaViolation",
                    $"Unexpected property '{prop.Name}' in backlog item at index {index}.",
                    Field: prop.Name));
            }
        }

        foreach (var required in RequiredItemProperties)
        {
            if (!propMap.ContainsKey(required))
            {
                errors.Add(new ValidationIssue(
                    "SchemaViolation",
                    $"Missing required property '{required}' in backlog item at index {index}.",
                    Field: required));
            }
        }

        ValidateStringField(index, propMap, "id", minLength: 1, maxLength: 64, IdPattern(), errors);
        ValidateStringField(index, propMap, "title", minLength: 1, maxLength: 200, null, errors);
        ValidateStringField(index, propMap, "description", minLength: 1, maxLength: null, null, errors);

        if (propMap.TryGetValue("priority", out var priorityProp))
        {
            if (priorityProp.Value.ValueKind != JsonValueKind.Number || !priorityProp.Value.TryGetInt32(out _))
            {
                errors.Add(new ValidationIssue("SchemaViolation", "Property 'priority' must be an integer.", Field: "priority"));
            }
        }

        if (propMap.TryGetValue("dependencies", out var depsProp))
        {
            if (depsProp.Value.ValueKind != JsonValueKind.Array)
            {
                errors.Add(new ValidationIssue("SchemaViolation", "Property 'dependencies' must be an array.", Field: "dependencies"));
            }
            else
            {
                var seen = new HashSet<string>(StringComparer.Ordinal);
                foreach (var dep in depsProp.Value.EnumerateArray())
                {
                    if (dep.ValueKind != JsonValueKind.String)
                    {
                        errors.Add(new ValidationIssue("SchemaViolation", "Dependencies must be strings.", Field: "dependencies"));
                        continue;
                    }

                    var depValue = dep.GetString() ?? "";
                    if (depValue.Length < 1 || depValue.Length > 64 || !IdPattern().IsMatch(depValue))
                    {
                        errors.Add(new ValidationIssue("SchemaViolation", $"Invalid dependency id '{depValue}'.", Field: "dependencies"));
                    }

                    if (!seen.Add(depValue))
                    {
                        errors.Add(new ValidationIssue("SchemaViolation", $"Duplicate dependency '{depValue}'.", Field: "dependencies"));
                    }
                }
            }
        }

        if (propMap.TryGetValue("status", out var statusProp))
        {
            if (statusProp.Value.ValueKind != JsonValueKind.String)
            {
                errors.Add(new ValidationIssue("SchemaViolation", "Property 'status' must be a string.", Field: "status"));
            }
            else
            {
                var status = statusProp.Value.GetString() ?? "";
                if (!AllowedStatuses.Contains(status))
                {
                    errors.Add(new ValidationIssue("SchemaViolation", $"Invalid status '{status}'.", Field: "status"));
                }
            }
        }

        ValidateDateTimeOrNull(index, propMap, "startedAt", errors);
        ValidateDateTimeOrNull(index, propMap, "doneAt", errors);
    }

    private static void ValidateStringField(
        int index,
        IReadOnlyDictionary<string, JsonProperty> propMap,
        string fieldName,
        int minLength,
        int? maxLength,
        Regex? regex,
        ICollection<ValidationIssue> errors)
    {
        if (!propMap.TryGetValue(fieldName, out var prop))
        {
            return;
        }

        if (prop.Value.ValueKind != JsonValueKind.String)
        {
            errors.Add(new ValidationIssue("SchemaViolation", $"Property '{fieldName}' must be a string.", Field: fieldName));
            return;
        }

        var value = prop.Value.GetString() ?? "";
        if (value.Length < minLength)
        {
            errors.Add(new ValidationIssue("SchemaViolation", $"Property '{fieldName}' must have length >= {minLength}.", Field: fieldName));
        }

        if (maxLength is not null && value.Length > maxLength.Value)
        {
            errors.Add(new ValidationIssue("SchemaViolation", $"Property '{fieldName}' must have length <= {maxLength.Value}.", Field: fieldName));
        }

        if (regex is not null && !regex.IsMatch(value))
        {
            errors.Add(new ValidationIssue("SchemaViolation", $"Property '{fieldName}' does not match required pattern.", Field: fieldName));
        }
    }

    private static void ValidateDateTimeOrNull(
        int index,
        IReadOnlyDictionary<string, JsonProperty> propMap,
        string fieldName,
        ICollection<ValidationIssue> errors)
    {
        if (!propMap.TryGetValue(fieldName, out var prop))
        {
            return;
        }

        if (prop.Value.ValueKind == JsonValueKind.Null)
        {
            return;
        }

        if (prop.Value.ValueKind != JsonValueKind.String)
        {
            errors.Add(new ValidationIssue("SchemaViolation", $"Property '{fieldName}' must be string or null.", Field: fieldName));
            return;
        }

        var raw = prop.Value.GetString() ?? "";
        if (!DateTimeOffset.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out _))
        {
            errors.Add(new ValidationIssue("SchemaViolation", $"Property '{fieldName}' must be a valid date-time string.", Field: fieldName));
        }
    }

    [GeneratedRegex("^[a-z0-9][a-z0-9._-]*$")]
    private static partial Regex IdPattern();
}
