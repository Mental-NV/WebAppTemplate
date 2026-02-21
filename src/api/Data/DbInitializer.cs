using Microsoft.EntityFrameworkCore;
using Api.Features.Todos;

namespace Api.Data;

public static class DbInitializer
{
    public static async Task InitializeAsync(WebApplication app, bool seedDefaults = true)
    {
        await using var scope = app.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();

        await db.Database.EnsureCreatedAsync();

        if (!seedDefaults)
            return;

        if (await db.Todos.AnyAsync())
            return;

        db.Todos.AddRange(
            new TodoItem { Title = "Buy milk", IsCompleted = false },
            new TodoItem { Title = "Walk 10k steps", IsCompleted = true },
            new TodoItem { Title = "Ship v1", IsCompleted = false }
        );

        await db.SaveChangesAsync();
    }
}
