using System.Data.Common;
using Api.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Api.Tests;

public sealed class E2eAuthWebApplicationFactory : WebApplicationFactory<Program>
{
    private DbConnection? _connection;

    public E2eAuthWebApplicationFactory()
    {
        Environment.SetEnvironmentVariable("Google__ClientId", "ci-test.apps.googleusercontent.com");
        Environment.SetEnvironmentVariable("Jwt__Issuer", "AppTemplate");
        Environment.SetEnvironmentVariable("Jwt__Audience", "AppTemplate");
        Environment.SetEnvironmentVariable("Jwt__SigningKey", "ci_test_signing_key_32_chars_minimum_123456");
        Environment.SetEnvironmentVariable("Jwt__AccessTokenMinutes", "60");
        Environment.SetEnvironmentVariable("E2E_AUTH_ENABLED", "true");
        Environment.SetEnvironmentVariable("E2E_AUTH_SECRET", "test-secret");
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("E2E");

        builder.ConfigureAppConfiguration((_, config) =>
        {
            config.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Google:ClientId"] = "ci-test.apps.googleusercontent.com",
                ["Jwt:Issuer"] = "AppTemplate",
                ["Jwt:Audience"] = "AppTemplate",
                ["Jwt:SigningKey"] = "ci_test_signing_key_32_chars_minimum_123456",
                ["Jwt:AccessTokenMinutes"] = "60",
                ["E2E_AUTH_ENABLED"] = "true",
                ["E2E_AUTH_SECRET"] = "test-secret"
            });
        });

        builder.ConfigureServices(services =>
        {
            var descriptors = services.Where(d => d.ServiceType == typeof(DbContextOptions<AppDbContext>)).ToList();
            foreach (var d in descriptors)
            {
                services.Remove(d);
            }

            _connection = new SqliteConnection("Data Source=:memory:");
            _connection.Open();

            services.AddDbContext<AppDbContext>(opt => opt.UseSqlite(_connection));

            var sp = services.BuildServiceProvider();
            using var scope = sp.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Database.EnsureCreated();
        });
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);
        if (disposing)
        {
            _connection?.Dispose();
            _connection = null;
        }
    }
}
