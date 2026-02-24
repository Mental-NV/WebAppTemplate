using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Ralph.BacklogCli;

internal static class Program
{
    private const string DefaultBacklogPath = ".ralph/backlog.json";
    private const string DefaultSchemaPath = ".ralph/backlog.schema.json";
    private const string DefaultSort = "priority-desc,id-asc";

    private static readonly JsonSerializerOptions OutputJsonOptions = CreateOutputJsonOptions();

    public static int Main(string[] args)
    {
        try
        {
            var invocation = ParsedInvocation.Parse(args);
            var command = invocation.CommandKey;

            return command switch
            {
                "validate" => RunValidate(invocation),
                "add" => RunAdd(invocation),
                "list" => RunList(invocation),
                "show" => RunShow(invocation),
                "active" => RunActive(invocation),
                "next" => RunNext(invocation),
                "take-next" => RunTakeNext(invocation),
                "status set" => RunStatusSet(invocation),
                _ => WriteAndReturnError(2, command, "UsageError", $"Unknown command '{command}'.")
            };
        }
        catch (CommandUsageException ex)
        {
            return WriteAndReturnError(2, ex.Command, "UsageError", ex.Message, ex.Details);
        }
        catch (CommandValidationException ex)
        {
            return WriteAndReturnError(1, ex.Command, ex.Code, ex.Message, ex.Details);
        }
        catch (CommandIoException ex)
        {
            return WriteAndReturnError(3, ex.Command, ex.Code, ex.Message, ex.Details);
        }
        catch (Exception ex)
        {
            return WriteAndReturnError(3, "unknown", "UnhandledError", ex.Message);
        }
    }

    private static int RunValidate(ParsedInvocation invocation)
    {
        var paths = invocation.ResolvePaths();
        var validation = ValidateBacklog(paths.SchemaPath, paths.BacklogPath);
        if (validation.Errors.Count > 0)
        {
            return WriteAndReturnError(
                1,
                "validate",
                "BacklogInvalid",
                "Backlog validation failed.",
                new
                {
                    errors = validation.Errors.Select(ToValidationIssueDto).ToArray()
                });
        }

        WriteJson(new
        {
            ok = true,
            command = "validate",
            data = new
            {
                version = validation.Document!.Version,
                itemCount = validation.Document.Items.Count,
                activeCount = validation.Document.Items.Count(x => x.Status is BacklogStatus.InProgress or BacklogStatus.InReview),
                errors = Array.Empty<object>()
            }
        });

        return 0;
    }

    private static int RunAdd(ParsedInvocation invocation)
    {
        var paths = invocation.ResolvePaths();
        using var _ = FileLocking.AcquireExclusiveLock(BacklogStore.GetLockFilePath(paths.BacklogPath));

        var validation = RequireValidBacklog("add", paths.SchemaPath, paths.BacklogPath);
        var document = validation.Document!;

        var id = invocation.RequireOption("add", "id");
        var title = invocation.RequireOption("add", "title");
        var description = invocation.GetOption("description");
        var descriptionFile = invocation.GetOption("description-file");

        if (description is null && descriptionFile is null)
        {
            throw new CommandUsageException("add", "Either --description or --description-file is required.");
        }

        if (description is not null && descriptionFile is not null)
        {
            throw new CommandUsageException("add", "Use only one of --description or --description-file.");
        }

        var resolvedDescription = description ?? ReadDescriptionFile(descriptionFile!);

        if (!int.TryParse(invocation.RequireOption("add", "priority"), out var priority))
        {
            throw new CommandUsageException("add", "Option --priority must be an integer.");
        }

        var depends = invocation.GetOptionValues("depends")
            .SelectMany(ParseCsv)
            .Distinct(StringComparer.Ordinal)
            .ToList();

        var item = new BacklogItem
        {
            Id = id,
            Title = title,
            Description = resolvedDescription,
            Priority = priority,
            Dependencies = depends,
            Status = BacklogStatus.New,
            StartedAt = null,
            DoneAt = null
        };

        document.Items.Add(item);
        EnsureRuntimeValidOrThrow("add", document);
        BacklogStore.Save(paths.BacklogPath, document);

        WriteJson(new
        {
            ok = true,
            command = "add",
            data = new
            {
                item
            }
        });

        return 0;
    }

    private static int RunList(ParsedInvocation invocation)
    {
        var paths = invocation.ResolvePaths();
        var document = RequireValidBacklog("list", paths.SchemaPath, paths.BacklogPath).Document!;

        var statusFilters = ParseStatusFilters(invocation.GetOptionValues("status"), "list");
        bool? eligibleFilter = null;
        var eligibleOpt = invocation.GetOption("eligible");
        if (eligibleOpt is not null)
        {
            if (!bool.TryParse(eligibleOpt, out var parsed))
            {
                throw new CommandUsageException("list", "Option --eligible must be true or false.");
            }

            eligibleFilter = parsed;
        }

        var sort = invocation.GetOption("sort") ?? DefaultSort;
        var eligibleIds = BacklogValidator.GetEligibleNewItems(document).Select(x => x.Id).ToHashSet(StringComparer.Ordinal);

        IEnumerable<BacklogItem> items = document.Items;
        if (statusFilters.Count > 0)
        {
            items = items.Where(x => statusFilters.Contains(x.Status));
        }

        if (eligibleFilter is not null)
        {
            items = eligibleFilter.Value
                ? items.Where(x => eligibleIds.Contains(x.Id))
                : items.Where(x => !eligibleIds.Contains(x.Id));
        }

        items = ApplySort(items, sort, "list");

        var result = items.ToList();
        WriteJson(new
        {
            ok = true,
            command = "list",
            data = new
            {
                count = result.Count,
                items = result
            }
        });

        return 0;
    }

    private static int RunShow(ParsedInvocation invocation)
    {
        var paths = invocation.ResolvePaths();
        var document = RequireValidBacklog("show", paths.SchemaPath, paths.BacklogPath).Document!;
        var id = invocation.RequireOption("show", "id");
        var item = document.Items.SingleOrDefault(x => string.Equals(x.Id, id, StringComparison.Ordinal));

        if (item is null)
        {
            WriteJson(new { ok = true, command = "show", data = new { found = false } });
        }
        else
        {
            WriteJson(new { ok = true, command = "show", data = new { found = true, item } });
        }

        return 0;
    }

    private static int RunActive(ParsedInvocation invocation)
    {
        var paths = invocation.ResolvePaths();
        var document = RequireValidBacklog("active", paths.SchemaPath, paths.BacklogPath).Document!;
        var item = BacklogValidator.GetActiveItem(document);
        if (item is null)
        {
            WriteJson(new { ok = true, command = "active", data = new { found = false } });
        }
        else
        {
            WriteJson(new { ok = true, command = "active", data = new { found = true, item } });
        }

        return 0;
    }

    private static int RunNext(ParsedInvocation invocation)
    {
        var paths = invocation.ResolvePaths();
        var document = RequireValidBacklog("next", paths.SchemaPath, paths.BacklogPath).Document!;
        var eligible = BacklogValidator.GetEligibleNewItems(document);
        var item = eligible.FirstOrDefault();

        if (item is null)
        {
            WriteJson(new { ok = true, command = "next", data = new { found = false, eligibleCount = 0, sort = DefaultSort } });
        }
        else
        {
            WriteJson(new { ok = true, command = "next", data = new { found = true, item, eligibleCount = eligible.Count, sort = DefaultSort } });
        }

        return 0;
    }

    private static int RunTakeNext(ParsedInvocation invocation)
    {
        var paths = invocation.ResolvePaths();
        using var _ = FileLocking.AcquireExclusiveLock(BacklogStore.GetLockFilePath(paths.BacklogPath));

        var validation = RequireValidBacklog("take-next", paths.SchemaPath, paths.BacklogPath);
        var document = validation.Document!;

        var active = BacklogValidator.GetActiveItem(document);
        if (active is not null)
        {
            throw new CommandValidationException(
                "take-next",
                "ActiveItemExists",
                "Cannot take next item while another item is active.",
                new { activeItemId = active.Id, status = active.Status.ToString() });
        }

        var eligible = BacklogValidator.GetEligibleNewItems(document);
        if (eligible.Count == 0)
        {
            WriteJson(new
            {
                ok = true,
                command = "take-next",
                data = new
                {
                    found = false,
                    reason = "NoEligibleItems"
                }
            });
            return 0;
        }

        var item = eligible[0];
        BacklogValidator.ApplyStatusTransition(item, BacklogStatus.InProgress, DateTimeOffset.UtcNow);
        EnsureRuntimeValidOrThrow("take-next", document);
        BacklogStore.Save(paths.BacklogPath, document);

        WriteJson(new
        {
            ok = true,
            command = "take-next",
            data = new
            {
                found = true,
                item,
                eligibleCountBeforeTake = eligible.Count
            }
        });

        return 0;
    }

    private static int RunStatusSet(ParsedInvocation invocation)
    {
        var paths = invocation.ResolvePaths();
        using var _ = FileLocking.AcquireExclusiveLock(BacklogStore.GetLockFilePath(paths.BacklogPath));

        var document = RequireValidBacklog("status set", paths.SchemaPath, paths.BacklogPath).Document!;
        var id = invocation.RequireOption("status set", "id");
        var toRaw = invocation.RequireOption("status set", "to");

        if (!Enum.TryParse<BacklogStatus>(toRaw, ignoreCase: false, out var to))
        {
            throw new CommandUsageException("status set", $"Invalid status '{toRaw}'.");
        }

        var item = document.Items.SingleOrDefault(x => string.Equals(x.Id, id, StringComparison.Ordinal));
        if (item is null)
        {
            throw new CommandValidationException("status set", "ItemNotFound", $"Backlog item '{id}' was not found.", new { id });
        }

        var from = item.Status;
        var transitionIssue = BacklogValidator.ValidateStatusTransition(from, to, item.Id);
        if (transitionIssue is not null)
        {
            throw new CommandValidationException(
                "status set",
                transitionIssue.Code,
                transitionIssue.Message,
                new { id = item.Id, from = from.ToString(), to = to.ToString() });
        }

        BacklogValidator.ApplyStatusTransition(item, to, DateTimeOffset.UtcNow);
        EnsureRuntimeValidOrThrow("status set", document);
        BacklogStore.Save(paths.BacklogPath, document);

        WriteJson(new
        {
            ok = true,
            command = "status set",
            data = new
            {
                itemId = item.Id,
                from = from.ToString(),
                to = to.ToString(),
                item
            }
        });

        return 0;
    }

    private static ValidationResult ValidateBacklog(string schemaPath, string backlogPath)
    {
        var errors = new List<ValidationIssue>();
        BacklogDocument? document = null;

        try
        {
            errors.AddRange(JsonSchemaValidator.Validate(schemaPath, backlogPath));
        }
        catch (FileNotFoundException ex)
        {
            throw new CommandIoException("validate", "SchemaLoadError", ex.Message);
        }
        catch (InvalidDataException ex)
        {
            throw new CommandIoException("validate", "SchemaLoadError", ex.Message);
        }
        catch (IOException ex)
        {
            throw new CommandIoException("validate", "FileReadError", ex.Message);
        }
        catch (UnauthorizedAccessException ex)
        {
            throw new CommandIoException("validate", "FileReadError", ex.Message);
        }
        catch (JsonException ex)
        {
            errors.Add(new ValidationIssue("InvalidJson", ex.Message));
        }

        if (errors.Count == 0)
        {
            try
            {
                document = BacklogStore.Load(backlogPath);
            }
            catch (JsonException ex)
            {
                errors.Add(new ValidationIssue("InvalidJson", ex.Message));
            }
            catch (IOException ex)
            {
                throw new CommandIoException("validate", "FileReadError", ex.Message);
            }
            catch (UnauthorizedAccessException ex)
            {
                throw new CommandIoException("validate", "FileReadError", ex.Message);
            }
            catch (InvalidDataException ex)
            {
                errors.Add(new ValidationIssue("InvalidJson", ex.Message));
            }
        }

        if (document is not null)
        {
            errors.AddRange(BacklogValidator.ValidateRuntime(document));
        }

        return new ValidationResult(document, errors);
    }

    private static ValidationResult RequireValidBacklog(string command, string schemaPath, string backlogPath)
    {
        try
        {
            var result = ValidateBacklog(schemaPath, backlogPath);
            if (result.Errors.Count > 0)
            {
                throw new CommandValidationException(
                    command,
                    "BacklogInvalid",
                    "Backlog validation failed.",
                    new { errors = result.Errors.Select(ToValidationIssueDto).ToArray() });
            }

            return result;
        }
        catch (CommandIoException ex) when (ex.Command == "validate")
        {
            throw new CommandIoException(command, ex.Code, ex.Message, ex.Details);
        }
    }

    private static void EnsureRuntimeValidOrThrow(string command, BacklogDocument document)
    {
        var issues = BacklogValidator.ValidateRuntime(document);
        if (issues.Count == 0)
        {
            return;
        }

        throw new CommandValidationException(
            command,
            "BacklogInvalid",
            "Backlog validation failed after mutation.",
            new { errors = issues.Select(ToValidationIssueDto).ToArray() });
    }

    private static IReadOnlyCollection<BacklogStatus> ParseStatusFilters(IReadOnlyList<string> rawValues, string command)
    {
        var result = new HashSet<BacklogStatus>();
        foreach (var raw in rawValues)
        {
            if (!Enum.TryParse<BacklogStatus>(raw, ignoreCase: false, out var status))
            {
                throw new CommandUsageException(command, $"Invalid --status value '{raw}'.");
            }

            result.Add(status);
        }

        return result;
    }

    private static IEnumerable<BacklogItem> ApplySort(IEnumerable<BacklogItem> items, string sort, string command)
    {
        return sort switch
        {
            "priority-desc" or "priority-desc,id-asc" => items.OrderByDescending(x => x.Priority).ThenBy(x => x.Id, StringComparer.Ordinal),
            "priority-asc" or "priority-asc,id-asc" => items.OrderBy(x => x.Priority).ThenBy(x => x.Id, StringComparer.Ordinal),
            "id-asc" => items.OrderBy(x => x.Id, StringComparer.Ordinal),
            _ => throw new CommandUsageException(command, $"Invalid --sort value '{sort}'.")
        };
    }

    private static IEnumerable<string> ParseCsv(string raw)
    {
        return raw.Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
    }

    private static string ReadDescriptionFile(string path)
    {
        try
        {
            return File.ReadAllText(path);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            throw new CommandIoException("add", "FileReadError", $"Failed to read description file '{path}'. {ex.Message}");
        }
    }

    private static object ToValidationIssueDto(ValidationIssue issue)
    {
        var data = new Dictionary<string, object?>(StringComparer.Ordinal)
        {
            ["code"] = issue.Code,
            ["message"] = issue.Message
        };

        if (!string.IsNullOrWhiteSpace(issue.ItemId))
        {
            data["itemId"] = issue.ItemId;
        }

        if (!string.IsNullOrWhiteSpace(issue.DependencyId))
        {
            data["dependencyId"] = issue.DependencyId;
        }

        if (!string.IsNullOrWhiteSpace(issue.Field))
        {
            data["field"] = issue.Field;
        }

        return data;
    }

    private static int WriteAndReturnError(int exitCode, string command, string code, string message, object? details = null)
    {
        WriteJson(new
        {
            ok = false,
            command,
            error = new
            {
                code,
                message,
                details
            }
        });

        return exitCode;
    }

    private static void WriteJson(object value)
    {
        Console.Out.WriteLine(JsonSerializer.Serialize(value, OutputJsonOptions));
    }

    private static JsonSerializerOptions CreateOutputJsonOptions()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = true,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
        };
        options.Converters.Add(new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false));
        return options;
    }

    private sealed record ValidationResult(BacklogDocument? Document, List<ValidationIssue> Errors);

    private sealed class ParsedInvocation
    {
        private ParsedInvocation(string commandKey, Dictionary<string, List<string>> options)
        {
            CommandKey = commandKey;
            Options = options;
        }

        public string CommandKey { get; }
        public Dictionary<string, List<string>> Options { get; }

        public static ParsedInvocation Parse(string[] args)
        {
            if (args.Length == 0)
            {
                throw new CommandUsageException("unknown", "No command was provided.");
            }

            var commandParts = new List<string>();
            var index = 0;
            while (index < args.Length && !args[index].StartsWith("--", StringComparison.Ordinal))
            {
                commandParts.Add(args[index]);
                index++;
            }

            if (commandParts.Count == 0)
            {
                throw new CommandUsageException("unknown", "No command was provided.");
            }

            var commandKey = string.Join(' ', commandParts);
            var options = new Dictionary<string, List<string>>(StringComparer.Ordinal);

            while (index < args.Length)
            {
                var token = args[index];
                if (!token.StartsWith("--", StringComparison.Ordinal))
                {
                    throw new CommandUsageException(commandKey, $"Unexpected argument '{token}'.");
                }

                var name = token[2..];
                if (string.IsNullOrWhiteSpace(name))
                {
                    throw new CommandUsageException(commandKey, "Invalid option name '--'.");
                }

                string value;
                if (index + 1 < args.Length && !args[index + 1].StartsWith("--", StringComparison.Ordinal))
                {
                    value = args[index + 1];
                    index += 2;
                }
                else
                {
                    value = "true";
                    index += 1;
                }

                if (!options.TryGetValue(name, out var values))
                {
                    values = [];
                    options[name] = values;
                }

                values.Add(value);
            }

            return new ParsedInvocation(commandKey, options);
        }

        public (string BacklogPath, string SchemaPath) ResolvePaths()
        {
            var backlogPath = GetOption("backlog") ?? DefaultBacklogPath;
            var schemaPath = GetOption("schema") ?? DefaultSchemaPath;
            return (backlogPath, schemaPath);
        }

        public string? GetOption(string name)
        {
            if (!Options.TryGetValue(name, out var values) || values.Count == 0)
            {
                return null;
            }

            return values[^1];
        }

        public IReadOnlyList<string> GetOptionValues(string name)
        {
            if (!Options.TryGetValue(name, out var values))
            {
                return Array.Empty<string>();
            }

            return values;
        }

        public string RequireOption(string command, string name)
        {
            var value = GetOption(name);
            if (string.IsNullOrWhiteSpace(value))
            {
                throw new CommandUsageException(command, $"Missing required option --{name}.");
            }

            return value;
        }
    }

    private sealed class CommandUsageException(string command, string message)
        : Exception(message)
    {
        public string Command { get; } = command;
        public object? Details { get; init; }
    }

    private sealed class CommandValidationException(string command, string code, string message, object? details = null)
        : Exception(message)
    {
        public string Command { get; } = command;
        public string Code { get; } = code;
        public object? Details { get; } = details;
    }

    private sealed class CommandIoException(string command, string code, string message, object? details = null)
        : Exception(message)
    {
        public string Command { get; } = command;
        public string Code { get; } = code;
        public object? Details { get; } = details;
    }
}
