using System.Security.Claims;
using Api.Features.Auth;
using Api.UnitTests.TestInfrastructure;

namespace Api.UnitTests.Auth;

public sealed class MeTests
{
    [Fact]
    public async Task Handle_PrefersSubClaim_OverNameIdentifier()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim("sub", "sub-value"),
            new Claim(ClaimTypes.NameIdentifier, "name-id"),
            new Claim(ClaimTypes.Email, "user@example.com"),
            new Claim(ClaimTypes.Name, "User Name")
        ]));

        var result = Me.Handle(principal);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        Assert.Equal(StatusCodes.Status200OK, executed.StatusCode);
        using var json = ResultTestHelper.ParseJson(executed.Body);
        Assert.Equal("sub-value", json.RootElement.GetProperty("subject").GetString());
        Assert.Equal("user@example.com", json.RootElement.GetProperty("email").GetString());
        Assert.Equal("User Name", json.RootElement.GetProperty("name").GetString());
    }

    [Fact]
    public async Task Handle_FallsBackToNameIdentifier_WhenSubMissing()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity(
        [
            new Claim(ClaimTypes.NameIdentifier, "fallback-sub")
        ]));

        var result = Me.Handle(principal);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        using var json = ResultTestHelper.ParseJson(executed.Body);
        Assert.Equal("fallback-sub", json.RootElement.GetProperty("subject").GetString());
        Assert.Equal(JsonValueKind.Null, json.RootElement.GetProperty("email").ValueKind);
        Assert.Equal(JsonValueKind.Null, json.RootElement.GetProperty("name").ValueKind);
    }

    [Fact]
    public async Task Handle_ReturnsEmptySubject_WhenNoSubjectClaims()
    {
        var principal = new ClaimsPrincipal(new ClaimsIdentity());

        var result = Me.Handle(principal);
        var executed = await ResultTestHelper.ExecuteAsync(result);

        using var json = ResultTestHelper.ParseJson(executed.Body);
        Assert.Equal(string.Empty, json.RootElement.GetProperty("subject").GetString());
    }
}
