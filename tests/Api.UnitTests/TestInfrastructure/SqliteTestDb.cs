using Api.Data;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;

namespace Api.UnitTests.TestInfrastructure;

internal sealed class SqliteTestDb : IDisposable
{
    private readonly SqliteConnection _connection;

    public AppDbContext Db { get; }

    private SqliteTestDb(SqliteConnection connection, AppDbContext db)
    {
        _connection = connection;
        Db = db;
    }

    public static SqliteTestDb Create()
    {
        var connection = new SqliteConnection("Data Source=:memory:");
        connection.Open();

        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseSqlite(connection)
            .Options;

        var db = new AppDbContext(options);
        db.Database.EnsureCreated();

        return new SqliteTestDb(connection, db);
    }

    public void Dispose()
    {
        Db.Dispose();
        _connection.Dispose();
    }
}
