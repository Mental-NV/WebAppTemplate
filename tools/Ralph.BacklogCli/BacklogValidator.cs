namespace Ralph.BacklogCli;

public static class BacklogValidator
{
    public static List<ValidationIssue> ValidateRuntime(BacklogDocument document)
    {
        var issues = new List<ValidationIssue>();

        var idMap = new Dictionary<string, BacklogItem>(StringComparer.Ordinal);
        foreach (var item in document.Items)
        {
            if (!idMap.TryAdd(item.Id, item))
            {
                issues.Add(new ValidationIssue(
                    "DuplicateId",
                    $"Duplicate backlog item id '{item.Id}'.",
                    ItemId: item.Id));
            }
        }

        foreach (var item in document.Items)
        {
            foreach (var dep in item.Dependencies)
            {
                if (string.Equals(item.Id, dep, StringComparison.Ordinal))
                {
                    issues.Add(new ValidationIssue(
                        "SelfDependency",
                        $"Backlog item '{item.Id}' depends on itself.",
                        ItemId: item.Id,
                        DependencyId: dep));
                    continue;
                }

                if (!idMap.ContainsKey(dep))
                {
                    issues.Add(new ValidationIssue(
                        "MissingDependency",
                        $"Dependency '{dep}' does not exist.",
                        ItemId: item.Id,
                        DependencyId: dep));
                }
            }
        }

        DetectCycles(document, issues);

        var activeItems = document.Items
            .Where(x => x.Status is BacklogStatus.InProgress or BacklogStatus.InReview)
            .ToList();

        if (activeItems.Count > 1)
        {
            issues.Add(new ValidationIssue(
                "TooManyActiveItems",
                $"Expected at most one active item, found {activeItems.Count}."));
        }

        foreach (var item in document.Items)
        {
            switch (item.Status)
            {
                case BacklogStatus.New:
                    if (item.StartedAt is not null)
                    {
                        issues.Add(new ValidationIssue(
                            "InvalidTimestampsForStatus",
                            "New item must have startedAt = null.",
                            ItemId: item.Id,
                            Field: "startedAt"));
                    }

                    if (item.DoneAt is not null)
                    {
                        issues.Add(new ValidationIssue(
                            "InvalidTimestampsForStatus",
                            "New item must have doneAt = null.",
                            ItemId: item.Id,
                            Field: "doneAt"));
                    }

                    break;

                case BacklogStatus.InProgress:
                case BacklogStatus.InReview:
                    if (item.StartedAt is null)
                    {
                        issues.Add(new ValidationIssue(
                            "InvalidTimestampsForStatus",
                            $"{item.Status} item must have startedAt set.",
                            ItemId: item.Id,
                            Field: "startedAt"));
                    }

                    if (item.DoneAt is not null)
                    {
                        issues.Add(new ValidationIssue(
                            "InvalidTimestampsForStatus",
                            $"{item.Status} item must have doneAt = null.",
                            ItemId: item.Id,
                            Field: "doneAt"));
                    }

                    break;

                case BacklogStatus.Done:
                    if (item.StartedAt is null)
                    {
                        issues.Add(new ValidationIssue(
                            "InvalidTimestampsForStatus",
                            "Done item must have startedAt set.",
                            ItemId: item.Id,
                            Field: "startedAt"));
                    }

                    if (item.DoneAt is null)
                    {
                        issues.Add(new ValidationIssue(
                            "InvalidTimestampsForStatus",
                            "Done item must have doneAt set.",
                            ItemId: item.Id,
                            Field: "doneAt"));
                    }

                    break;
            }
        }

        return issues;
    }

    public static BacklogItem? GetActiveItem(BacklogDocument document)
    {
        return document.Items.SingleOrDefault(x => x.Status is BacklogStatus.InProgress or BacklogStatus.InReview);
    }

    public static IReadOnlyList<BacklogItem> GetEligibleNewItems(BacklogDocument document)
    {
        var doneSet = document.Items
            .Where(x => x.Status == BacklogStatus.Done)
            .Select(x => x.Id)
            .ToHashSet(StringComparer.Ordinal);

        return document.Items
            .Where(x => x.Status == BacklogStatus.New)
            .Where(x => x.Dependencies.All(doneSet.Contains))
            .OrderByDescending(x => x.Priority)
            .ThenBy(x => x.Id, StringComparer.Ordinal)
            .ToList();
    }

    public static ValidationIssue? ValidateStatusTransition(BacklogStatus from, BacklogStatus to, string itemId)
    {
        var allowed = (from, to) switch
        {
            (BacklogStatus.New, BacklogStatus.InProgress) => true,
            (BacklogStatus.InProgress, BacklogStatus.InReview) => true,
            (BacklogStatus.InReview, BacklogStatus.InProgress) => true,
            (BacklogStatus.InReview, BacklogStatus.Done) => true,
            _ => false
        };

        if (allowed)
        {
            return null;
        }

        return new ValidationIssue(
            "InvalidTransition",
            $"Transition {from} -> {to} is not allowed.",
            ItemId: itemId);
    }

    public static void ApplyStatusTransition(BacklogItem item, BacklogStatus to, DateTimeOffset nowUtc)
    {
        if (to == BacklogStatus.InProgress && item.StartedAt is null)
        {
            item.StartedAt = nowUtc;
        }

        if (to == BacklogStatus.Done)
        {
            item.StartedAt ??= nowUtc;
            item.DoneAt = nowUtc;
        }
        else
        {
            item.DoneAt = null;
        }

        item.Status = to;
    }

    private static void DetectCycles(BacklogDocument document, ICollection<ValidationIssue> issues)
    {
        var map = document.Items.ToDictionary(x => x.Id, x => x, StringComparer.Ordinal);
        var state = new Dictionary<string, int>(StringComparer.Ordinal);
        var stack = new Stack<string>();

        foreach (var item in document.Items)
        {
            Visit(item.Id);
        }

        void Visit(string id)
        {
            if (!map.ContainsKey(id))
            {
                return;
            }

            if (state.TryGetValue(id, out var s))
            {
                if (s == 2)
                {
                    return;
                }

                if (s == 1)
                {
                    var cycle = stack.Reverse().SkipWhile(x => !string.Equals(x, id, StringComparison.Ordinal)).ToList();
                    cycle.Add(id);
                    issues.Add(new ValidationIssue(
                        "DependencyCycle",
                        $"Dependency cycle detected: {string.Join(" -> ", cycle)}.",
                        ItemId: id));
                }

                return;
            }

            state[id] = 1;
            stack.Push(id);

            foreach (var dep in map[id].Dependencies)
            {
                Visit(dep);
            }

            stack.Pop();
            state[id] = 2;
        }
    }
}
