using Api.Data;
using Microsoft.EntityFrameworkCore;

namespace Api.Features.Todos;

public static class DeleteTodo
{
    public static async Task<IResult> Handle(int id, AppDbContext db, CancellationToken ct)
    {
        var item = await db.Todos.FirstOrDefaultAsync(x => x.Id == id, ct);
        if (item is null) return Results.NotFound();

        db.Todos.Remove(item);
        await db.SaveChangesAsync(ct);

        return Results.NoContent();
    }
}
