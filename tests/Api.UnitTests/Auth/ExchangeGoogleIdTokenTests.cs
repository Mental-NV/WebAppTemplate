using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Api.Features.Auth;
using Api.UnitTests.TestInfrastructure;
using Google.Apis.Auth;
using Microsoft.Extensions.Options;

namespace Api.UnitTests.Auth;

public sealed class ExchangeGoogleIdTokenTests
{
    [Fact]
    public async Task Handle_ReturnsBadRequest_WhenIdTokenBlank()
    {
        var result = await ExchangeGoogleIdToken.Handle(
            new ExchangeGoogleIdToken.Request(" "),
            Options.Create(new GoogleOptions { ClientId = "abc.apps.googleusercontent.com" }),
            new FakeGoogleIdTokenValidator(),
            CreateJwtService(),
            new FakeWebHostEnvironment(),
            CancellationToken.None);

        var executed = await ResultTestHelper.ExecuteAsync(result);
        Assert.Equal(StatusCodes.Status400BadRequest, executed.StatusCode);
        using var json = ResultTestHelper.ParseJson(executed.Body);
        Assert.Equal("idToken is required", json.RootElement.GetProperty("error").GetString());
    }

    [Fact]
    public async Task Handle_ReturnsProblem_WhenGoogleClientIdMissing()
    {
        var result = await ExchangeGoogleIdToken.Handle(
            new ExchangeGoogleIdToken.Request("token"),
            Options.Create(new GoogleOptions { ClientId = "" }),
            new FakeGoogleIdTokenValidator(),
            CreateJwtService(),
            new FakeWebHostEnvironment(),
            CancellationToken.None);

        var executed = await ResultTestHelper.ExecuteAsync(result);
        Assert.Equal(StatusCodes.Status500InternalServerError, executed.StatusCode);
        using var json = ResultTestHelper.ParseJson(executed.Body);
        Assert.Equal("Google:ClientId is not configured.", json.RootElement.GetProperty("detail").GetString());
    }

    [Fact]
    public async Task Handle_ReturnsProblem_WhenGoogleClientIdPlaceholder()
    {
        var result = await ExchangeGoogleIdToken.Handle(
            new ExchangeGoogleIdToken.Request("token"),
            Options.Create(new GoogleOptions { ClientId = "REPLACE_ME.apps.googleusercontent.com" }),
            new FakeGoogleIdTokenValidator(),
            CreateJwtService(),
            new FakeWebHostEnvironment(),
            CancellationToken.None);

        var executed = await ResultTestHelper.ExecuteAsync(result);
        Assert.Equal(StatusCodes.Status500InternalServerError, executed.StatusCode);
        using var json = ResultTestHelper.ParseJson(executed.Body);
        Assert.Equal("Google:ClientId is still set to the placeholder value.", json.RootElement.GetProperty("detail").GetString());
    }

    [Fact]
    public async Task Handle_ReturnsDetailedJson401_InDevelopment_WhenValidationFails()
    {
        var validator = new FakeGoogleIdTokenValidator
        {
            ExceptionToThrow = new InvalidOperationException("bad token")
        };

        var result = await ExchangeGoogleIdToken.Handle(
            new ExchangeGoogleIdToken.Request("bad-id-token"),
            Options.Create(new GoogleOptions { ClientId = "abc.apps.googleusercontent.com" }),
            validator,
            CreateJwtService(),
            new FakeWebHostEnvironment { EnvironmentName = Environments.Development },
            CancellationToken.None);

        var executed = await ResultTestHelper.ExecuteAsync(result);
        Assert.Equal(StatusCodes.Status401Unauthorized, executed.StatusCode);
        using var json = ResultTestHelper.ParseJson(executed.Body);
        Assert.Equal("Invalid Google ID token", json.RootElement.GetProperty("error").GetString());
        Assert.Equal("bad token", json.RootElement.GetProperty("detail").GetString());
    }

    [Fact]
    public async Task Handle_ReturnsUnauthorized_InProduction_WhenValidationFails()
    {
        var validator = new FakeGoogleIdTokenValidator
        {
            ExceptionToThrow = new Exception("sensitive detail")
        };

        var result = await ExchangeGoogleIdToken.Handle(
            new ExchangeGoogleIdToken.Request("bad-id-token"),
            Options.Create(new GoogleOptions { ClientId = "abc.apps.googleusercontent.com" }),
            validator,
            CreateJwtService(),
            new FakeWebHostEnvironment { EnvironmentName = Environments.Production },
            CancellationToken.None);

        var executed = await ResultTestHelper.ExecuteAsync(result);
        Assert.Equal(StatusCodes.Status401Unauthorized, executed.StatusCode);
        Assert.True(string.IsNullOrEmpty(executed.Body));
    }

    [Fact]
    public async Task Handle_ReturnsOk_MapsUser_AndCreatesJwt_WhenValidationSucceeds()
    {
        var validator = new FakeGoogleIdTokenValidator
        {
            PayloadToReturn = new GoogleJsonWebSignature.Payload
            {
                Subject = "google-subject",
                Email = "user@example.com",
                Name = "Test User",
                Picture = "https://img.example/avatar.png"
            }
        };

        var result = await ExchangeGoogleIdToken.Handle(
            new ExchangeGoogleIdToken.Request("valid-google-token"),
            Options.Create(new GoogleOptions { ClientId = "abc.apps.googleusercontent.com" }),
            validator,
            CreateJwtService(),
            new FakeWebHostEnvironment { EnvironmentName = Environments.Production },
            CancellationToken.None);

        var executed = await ResultTestHelper.ExecuteAsync(result);
        Assert.Equal(StatusCodes.Status200OK, executed.StatusCode);
        Assert.Equal("valid-google-token", validator.LastIdToken);
        Assert.Equal("abc.apps.googleusercontent.com", validator.LastClientId);

        using var json = ResultTestHelper.ParseJson(executed.Body);
        var token = json.RootElement.GetProperty("accessToken").GetString();
        Assert.False(string.IsNullOrWhiteSpace(token));
        Assert.Equal("google-subject", json.RootElement.GetProperty("user").GetProperty("subject").GetString());
        Assert.Equal("user@example.com", json.RootElement.GetProperty("user").GetProperty("email").GetString());
        Assert.Equal("Test User", json.RootElement.GetProperty("user").GetProperty("name").GetString());
        Assert.Equal("https://img.example/avatar.png", json.RootElement.GetProperty("user").GetProperty("pictureUrl").GetString());

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        Assert.Contains(jwt.Claims, c => c.Type == "sub" && c.Value == "google-subject");
        Assert.Contains(jwt.Claims, c => c.Type == ClaimTypes.NameIdentifier && c.Value == "google-subject");
        Assert.Contains(jwt.Claims, c => c.Type == ClaimTypes.Email && c.Value == "user@example.com");
        Assert.Contains(jwt.Claims, c => c.Type == ClaimTypes.Name && c.Value == "Test User");
    }

    [Fact]
    public async Task Handle_OmitsOptionalClaims_WhenPayloadHasNoEmailOrName()
    {
        var validator = new FakeGoogleIdTokenValidator
        {
            PayloadToReturn = new GoogleJsonWebSignature.Payload
            {
                Subject = "google-subject",
                Email = null,
                Name = null
            }
        };

        var result = await ExchangeGoogleIdToken.Handle(
            new ExchangeGoogleIdToken.Request("valid-google-token"),
            Options.Create(new GoogleOptions { ClientId = "abc.apps.googleusercontent.com" }),
            validator,
            CreateJwtService(),
            new FakeWebHostEnvironment(),
            CancellationToken.None);

        var executed = await ResultTestHelper.ExecuteAsync(result);
        Assert.Equal(StatusCodes.Status200OK, executed.StatusCode);

        using var json = ResultTestHelper.ParseJson(executed.Body);
        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(json.RootElement.GetProperty("accessToken").GetString()!);
        Assert.Contains(jwt.Claims, c => c.Type == "sub" && c.Value == "google-subject");
        Assert.DoesNotContain(jwt.Claims, c => c.Type == ClaimTypes.Email);
        Assert.DoesNotContain(jwt.Claims, c => c.Type == ClaimTypes.Name);
        Assert.Equal(JsonValueKind.Null, json.RootElement.GetProperty("user").GetProperty("email").ValueKind);
        Assert.Equal(JsonValueKind.Null, json.RootElement.GetProperty("user").GetProperty("name").ValueKind);
    }

    private static JwtTokenService CreateJwtService()
    {
        return new JwtTokenService(Options.Create(new JwtOptions
        {
            Issuer = "test-issuer",
            Audience = "test-audience",
            SigningKey = new string('k', 40),
            AccessTokenMinutes = 30
        }));
    }
}
