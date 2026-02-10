using Api.Data;

namespace Api.Features.Todos;

public static class CreateTodo
{
    public sealed record Request(string Title);
    public sealed record Response(int Id, string Title, bool IsCompleted, DateTime CreatedAtUtc, DateTime? UpdatedAtUtc);

    public static async Task<IResult> Handle(Request req, AppDbContext db, HttpContext http, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Title))
            return Results.ValidationProblem(new Dictionary<string, string[]>
            {
                ["title"] = new[] { "Title is required." }
            });

        var item = new TodoItem
        {
            Title = req.Title.Trim(),
            IsCompleted = false,
            CreatedAtUtc = DateTime.UtcNow
        };

        db.Todos.Add(item);
        await db.SaveChangesAsync(ct);

        var res = new Response(item.Id, item.Title, item.IsCompleted, item.CreatedAtUtc, item.UpdatedAtUtc);

        var location = $"/api/v1/todos/{item.Id}";
        return Results.Created(location, res);
    }
}
