using Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Api.Features.Todos;

public static class GetTodo
{
    public sealed record TodoDto(int Id, string Title, bool IsCompleted, DateTime CreatedAtUtc, DateTime? UpdatedAtUtc);

    public static async Task<IResult> Handle(int id, AppDbContext db, CancellationToken ct)
    {
        var item = await db.Todos.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (item is null) return Results.NotFound();

        return Results.Ok(new TodoDto(item.Id, item.Title, item.IsCompleted, item.CreatedAtUtc, item.UpdatedAtUtc));
    }
}
