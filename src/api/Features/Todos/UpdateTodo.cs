using Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Api.Features.Todos;

public static class UpdateTodo
{
    public sealed record Request(string Title, bool IsCompleted);
    public sealed record Response(int Id, string Title, bool IsCompleted, DateTime CreatedAtUtc, DateTime? UpdatedAtUtc);

    public static async Task<IResult> Handle(int id, Request req, AppDbContext db, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.Title))
            return Results.ValidationProblem(new Dictionary<string, string[]>
            {
                ["title"] = new[] { "Title is required." }
            });

        var item = await db.Todos.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (item is null) return Results.NotFound();

        item.Title = req.Title.Trim();
        item.IsCompleted = req.IsCompleted;
        item.UpdatedAtUtc = DateTime.UtcNow;

        await db.SaveChangesAsync(ct);

        var res = new Response(item.Id, item.Title, item.IsCompleted, item.CreatedAtUtc, item.UpdatedAtUtc);
        return Results.Ok(res);
    }
}
