using Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Api.Features.Todos;

public static class ListTodos
{
    public sealed record TodoDto(int Id, string Title, bool IsCompleted, DateTime CreatedAtUtc, DateTime? UpdatedAtUtc);

    public static async Task<IResult> Handle(AppDbContext db, CancellationToken ct)
    {
        var items = await db.Todos
            .OrderByDescending(x => x.Id)
            .Select(x => new TodoDto(x.Id, x.Title, x.IsCompleted, x.CreatedAtUtc, x.UpdatedAtUtc))
            .ToListAsync(ct);

        return Results.Ok(items);
    }
}
