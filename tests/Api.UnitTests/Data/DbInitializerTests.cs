using Api.Data;
using Api.Features.Auth;
using Microsoft.AspNetCore.Builder;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;

namespace Api.UnitTests.Data;

public sealed class DbInitializerTests
{
    [Fact]
    public async Task InitializeAsync_SeedsThreeTodos_WhenDatabaseEmpty()
    {
        await using var app = await CreateAppAsync();

        await DbInitializer.InitializeAsync(app);

        await using var scope = app.Services.CreateAsyncScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var items = await db.Todos.OrderBy(x => x.Id).ToListAsync();

        Assert.Equal(3, items.Count);
        Assert.Equal("Buy milk", items[0].Title);
        Assert.False(items[0].IsCompleted);
        Assert.Equal("Walk 10k steps", items[1].Title);
        Assert.True(items[1].IsCompleted);
        Assert.Equal("Ship v1", items[2].Title);
        Assert.False(items[2].IsCompleted);
    }

    [Fact]
    public async Task InitializeAsync_DoesNotReseed_WhenDatabaseAlreadyHasData()
    {
        await using var app = await CreateAppAsync();

        await using (var scope = app.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Todos.Add(new Features.Todos.TodoItem { Title = "Existing" });
            await db.SaveChangesAsync();
        }

        await DbInitializer.InitializeAsync(app);

        await using var verifyScope = app.Services.CreateAsyncScope();
        var verifyDb = verifyScope.ServiceProvider.GetRequiredService<AppDbContext>();
        var items = await verifyDb.Todos.OrderBy(x => x.Id).ToListAsync();

        Assert.Single(items);
        Assert.Equal("Existing", items[0].Title);
    }

    private static async Task<WebApplication> CreateAppAsync()
    {
        var connection = new SqliteConnection("Data Source=:memory:");
        await connection.OpenAsync();

        var builder = WebApplication.CreateBuilder();
        builder.Services.AddDbContext<AppDbContext>(opt => opt.UseSqlite(connection));
        builder.Services.AddSingleton<JwtTokenService>(_ => new JwtTokenService(Options.Create(new JwtOptions
        {
            Issuer = "x",
            Audience = "y",
            SigningKey = new string('k', 32)
        })));
        builder.Services.AddSingleton<IGoogleIdTokenValidator, FakeNoopGoogleValidator>();

        var app = builder.Build();

        // Dispose the SQLite connection with the app lifetime to keep the in-memory DB alive.
        app.Lifetime.ApplicationStopped.Register(connection.Dispose);

        await using (var scope = app.Services.CreateAsyncScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            await db.Database.EnsureCreatedAsync();
        }

        return app;
    }

    private sealed class FakeNoopGoogleValidator : IGoogleIdTokenValidator
    {
        public Task<Google.Apis.Auth.GoogleJsonWebSignature.Payload> ValidateAsync(string idToken, string clientId, CancellationToken ct)
            => throw new NotImplementedException();
    }
}
