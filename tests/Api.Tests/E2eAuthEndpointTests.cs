using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;

namespace Api.Tests;

public sealed class E2eAuthEndpointTests : IClassFixture<E2eAuthWebApplicationFactory>, IClassFixture<CustomWebApplicationFactory>
{
    private readonly HttpClient _e2eClient;
    private readonly HttpClient _nonE2eClient;

    public E2eAuthEndpointTests(E2eAuthWebApplicationFactory e2eFactory, CustomWebApplicationFactory nonE2eFactory)
    {
        _e2eClient = e2eFactory.CreateClient(new()
        {
            BaseAddress = new Uri("http://localhost")
        });

        _nonE2eClient = nonE2eFactory.CreateClient(new()
        {
            BaseAddress = new Uri("http://localhost")
        });
    }

    [Fact]
    public async Task Login_endpoint_is_not_mapped_outside_e2e_environment()
    {
        var res = await _nonE2eClient.PostAsJsonAsync("/api/v1/test/auth/login", new { });

        Assert.Contains(res.StatusCode, new[] { HttpStatusCode.NotFound, HttpStatusCode.MethodNotAllowed });
    }

    [Fact]
    public async Task Login_returns_forbidden_when_secret_header_missing()
    {
        var res = await _e2eClient.PostAsJsonAsync("/api/v1/test/auth/login", new { });

        Assert.Equal(HttpStatusCode.Forbidden, res.StatusCode);
    }

    [Fact]
    public async Task Login_returns_forbidden_when_secret_header_is_wrong()
    {
        using var req = new HttpRequestMessage(HttpMethod.Post, "/api/v1/test/auth/login")
        {
            Content = JsonContent.Create(new { })
        };
        req.Headers.Add("X-E2E-Auth-Secret", "wrong-secret");

        var res = await _e2eClient.SendAsync(req);

        Assert.Equal(HttpStatusCode.Forbidden, res.StatusCode);
    }

    [Fact]
    public async Task Login_returns_app_jwt_that_can_call_me()
    {
        using var loginReq = new HttpRequestMessage(HttpMethod.Post, "/api/v1/test/auth/login")
        {
            Content = JsonContent.Create(new
            {
                subject = "e2e-test-sub",
                email = "e2e@example.test",
                name = "E2E Test User"
            })
        };
        loginReq.Headers.Add("X-E2E-Auth-Secret", "test-secret");

        var loginRes = await _e2eClient.SendAsync(loginReq);
        Assert.Equal(HttpStatusCode.OK, loginRes.StatusCode);

        var loginBody = await loginRes.Content.ReadFromJsonAsync<E2eLoginResponse>();
        Assert.NotNull(loginBody);
        Assert.False(string.IsNullOrWhiteSpace(loginBody!.AccessToken));
        Assert.Equal("e2e-test-sub", loginBody.User.Subject);

        using var meReq = new HttpRequestMessage(HttpMethod.Get, "/api/v1/auth/me");
        meReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", loginBody.AccessToken);

        var meRes = await _e2eClient.SendAsync(meReq);
        Assert.Equal(HttpStatusCode.OK, meRes.StatusCode);

        var meBody = await meRes.Content.ReadFromJsonAsync<MeResponse>();
        Assert.NotNull(meBody);
        Assert.Equal("e2e-test-sub", meBody!.Subject);
        Assert.Equal("e2e@example.test", meBody.Email);
        Assert.Equal("E2E Test User", meBody.Name);
    }

    private sealed record E2eLoginResponse(string AccessToken, DateTime ExpiresAtUtc, E2eUser User);
    private sealed record E2eUser(string Subject, string? Email, string? Name);
    private sealed record MeResponse(string Subject, string? Email, string? Name);
}
