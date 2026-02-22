using Api.Features.Todos;
using Api.UnitTests.TestInfrastructure;

namespace Api.UnitTests.Todos;

public sealed class TodoHandlerTests
{
    [Fact]
    public async Task CreateTodo_ReturnsValidationProblem_WhenTitleIsBlank()
    {
        using var db = SqliteTestDb.Create();

        var result = await CreateTodo.Handle(new CreateTodo.Request("   "), db.Db, new DefaultHttpContext(), CancellationToken.None);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status400BadRequest, executed.StatusCode);
        using var json = ResultTestHelper.ParseJson(executed.Body);
        var errors = json.RootElement.GetProperty("errors");
        Assert.Equal("Title is required.", errors.GetProperty("title")[0].GetString());
    }

    [Fact]
    public async Task CreateTodo_TrimsTitle_SetsDefaults_AndReturnsCreated()
    {
        using var db = SqliteTestDb.Create();

        var result = await CreateTodo.Handle(new CreateTodo.Request("  New Todo  "), db.Db, new DefaultHttpContext(), CancellationToken.None);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status201Created, executed.StatusCode);
        Assert.True(executed.Headers.TryGetValue("Location", out var location));
        Assert.StartsWith("/api/v1/todos/", location.ToString(), StringComparison.Ordinal);

        using var json = ResultTestHelper.ParseJson(executed.Body);
        Assert.Equal("New Todo", json.RootElement.GetProperty("title").GetString());
        Assert.False(json.RootElement.GetProperty("isCompleted").GetBoolean());
        Assert.True(json.RootElement.GetProperty("updatedAtUtc").ValueKind is JsonValueKind.Null);

        var saved = Assert.Single(db.Db.Todos);
        Assert.Equal("New Todo", saved.Title);
        Assert.False(saved.IsCompleted);
        Assert.Null(saved.UpdatedAtUtc);
        Assert.NotEqual(default, saved.CreatedAtUtc);
    }

    [Fact]
    public async Task ListTodos_ReturnsItemsOrderedByIdDescending()
    {
        using var db = SqliteTestDb.Create();
        db.Db.Todos.AddRange(
            new TodoItem { Title = "First" },
            new TodoItem { Title = "Second" },
            new TodoItem { Title = "Third" });
        await db.Db.SaveChangesAsync();

        var result = await ListTodos.Handle(db.Db, CancellationToken.None);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status200OK, executed.StatusCode);
        using var json = ResultTestHelper.ParseJson(executed.Body);
        var items = json.RootElement;
        Assert.Equal(3, items.GetArrayLength());
        Assert.Equal("Third", items[0].GetProperty("title").GetString());
        Assert.Equal("Second", items[1].GetProperty("title").GetString());
        Assert.Equal("First", items[2].GetProperty("title").GetString());
    }

    [Fact]
    public async Task GetTodo_ReturnsNotFound_WhenMissing()
    {
        using var db = SqliteTestDb.Create();

        var result = await GetTodo.Handle(123, db.Db, CancellationToken.None);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status404NotFound, executed.StatusCode);
    }

    [Fact]
    public async Task GetTodo_ReturnsDto_WhenFound()
    {
        using var db = SqliteTestDb.Create();
        var item = new TodoItem { Title = "Found", IsCompleted = true };
        db.Db.Todos.Add(item);
        await db.Db.SaveChangesAsync();

        var result = await GetTodo.Handle(item.Id, db.Db, CancellationToken.None);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status200OK, executed.StatusCode);
        using var json = ResultTestHelper.ParseJson(executed.Body);
        Assert.Equal(item.Id, json.RootElement.GetProperty("id").GetInt32());
        Assert.Equal("Found", json.RootElement.GetProperty("title").GetString());
        Assert.True(json.RootElement.GetProperty("isCompleted").GetBoolean());
    }

    [Fact]
    public async Task UpdateTodo_ReturnsValidationProblem_WhenTitleIsBlank()
    {
        using var db = SqliteTestDb.Create();

        var result = await UpdateTodo.Handle(1, new UpdateTodo.Request("", false), db.Db, CancellationToken.None);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status400BadRequest, executed.StatusCode);
        using var json = ResultTestHelper.ParseJson(executed.Body);
        Assert.Equal("Title is required.", json.RootElement.GetProperty("errors").GetProperty("title")[0].GetString());
    }

    [Fact]
    public async Task UpdateTodo_ReturnsNotFound_WhenMissing()
    {
        using var db = SqliteTestDb.Create();

        var result = await UpdateTodo.Handle(999, new UpdateTodo.Request("Updated", true), db.Db, CancellationToken.None);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status404NotFound, executed.StatusCode);
    }

    [Fact]
    public async Task UpdateTodo_TrimsTitle_UpdatesFields_AndPreservesCreatedAt()
    {
        using var db = SqliteTestDb.Create();
        var createdAt = DateTime.UtcNow.AddDays(-1);
        var item = new TodoItem { Title = "Old", IsCompleted = false, CreatedAtUtc = createdAt };
        db.Db.Todos.Add(item);
        await db.Db.SaveChangesAsync();

        var result = await UpdateTodo.Handle(item.Id, new UpdateTodo.Request("  Updated  ", true), db.Db, CancellationToken.None);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status200OK, executed.StatusCode);
        using var json = ResultTestHelper.ParseJson(executed.Body);
        Assert.Equal(item.Id, json.RootElement.GetProperty("id").GetInt32());
        Assert.Equal("Updated", json.RootElement.GetProperty("title").GetString());
        Assert.True(json.RootElement.GetProperty("isCompleted").GetBoolean());
        Assert.NotEqual(JsonValueKind.Null, json.RootElement.GetProperty("updatedAtUtc").ValueKind);

        var saved = await db.Db.Todos.FindAsync(item.Id);
        Assert.NotNull(saved);
        Assert.Equal("Updated", saved!.Title);
        Assert.True(saved.IsCompleted);
        Assert.Equal(createdAt, saved.CreatedAtUtc);
        Assert.NotNull(saved.UpdatedAtUtc);
        Assert.True(saved.UpdatedAtUtc >= createdAt);
    }

    [Fact]
    public async Task DeleteTodo_ReturnsNotFound_WhenMissing()
    {
        using var db = SqliteTestDb.Create();

        var result = await DeleteTodo.Handle(999, db.Db, CancellationToken.None);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status404NotFound, executed.StatusCode);
    }

    [Fact]
    public async Task DeleteTodo_RemovesItem_AndReturnsNoContent()
    {
        using var db = SqliteTestDb.Create();
        var item = new TodoItem { Title = "Delete me" };
        db.Db.Todos.Add(item);
        await db.Db.SaveChangesAsync();

        var result = await DeleteTodo.Handle(item.Id, db.Db, CancellationToken.None);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status204NoContent, executed.StatusCode);
        Assert.False(await db.Db.Todos.AnyAsync(x => x.Id == item.Id));
    }
}
