using System.Net;
using System.Net.Http.Json;

namespace Api.Tests;

public sealed class TodoCrudTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _client;

    public TodoCrudTests(CustomWebApplicationFactory factory)
    {
        _client = factory.CreateClient(new()
        {
            BaseAddress = new Uri("http://localhost")
        });
    }

    [Fact]
    public async Task Create_then_list_contains_item()
    {
        var create = new { title = "Test from xUnit" };
        var post = await _client.PostAsJsonAsync("/api/v1/todos", create);

        Assert.Equal(HttpStatusCode.Created, post.StatusCode);

        var list = await _client.GetFromJsonAsync<List<TodoDto>>("/api/v1/todos");
        Assert.NotNull(list);
        Assert.Contains(list!, x => x.Title == "Test from xUnit");
    }

    [Fact]
    public async Task Update_then_get_reflects_changes()
    {
        var post = await _client.PostAsJsonAsync("/api/v1/todos", new { title = "Initial" });
        var created = await post.Content.ReadFromJsonAsync<TodoDto>();
        Assert.NotNull(created);

        var put = await _client.PutAsJsonAsync($"/api/v1/todos/{created!.Id}", new { title = "Updated", isCompleted = true });
        Assert.Equal(HttpStatusCode.OK, put.StatusCode);

        var got = await _client.GetFromJsonAsync<TodoDto>($"/api/v1/todos/{created!.Id}");
        Assert.NotNull(got);
        Assert.Equal("Updated", got!.Title);
        Assert.True(got.IsCompleted);
    }

    private sealed record TodoDto(int Id, string Title, bool IsCompleted, DateTime CreatedAtUtc, DateTime? UpdatedAtUtc);
}
