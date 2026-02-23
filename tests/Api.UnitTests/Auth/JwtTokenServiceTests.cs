using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Api.Features.Auth;
using Microsoft.Extensions.Options;

namespace Api.UnitTests.Auth;

public sealed class JwtTokenServiceTests
{
    [Fact]
    public void CreateAccessToken_Throws_WhenSigningKeyMissing()
    {
        var service = new JwtTokenService(Options.Create(new JwtOptions
        {
            Issuer = "issuer",
            Audience = "aud",
            SigningKey = ""
        }));

        var ex = Assert.Throws<InvalidOperationException>(() => service.CreateAccessToken([]));
        Assert.Contains("Jwt:SigningKey is not configured.", ex.Message, StringComparison.Ordinal);
    }

    [Fact]
    public void CreateAccessToken_ReturnsToken_WithIssuerAudienceClaims_AndExpectedExpiration()
    {
        var nowBefore = DateTime.UtcNow;
        var options = new JwtOptions
        {
            Issuer = "app-issuer",
            Audience = "app-aud",
            SigningKey = new string('x', 40),
            AccessTokenMinutes = 15
        };
        var service = new JwtTokenService(Options.Create(options));
        var claims = new[]
        {
            new Claim("sub", "user-123"),
            new Claim(ClaimTypes.Email, "user@example.com")
        };

        var (token, exp) = service.CreateAccessToken(claims);
        var nowAfter = DateTime.UtcNow;

        Assert.False(string.IsNullOrWhiteSpace(token));
        Assert.InRange(exp, nowBefore.AddMinutes(15).AddSeconds(-5), nowAfter.AddMinutes(15).AddSeconds(5));

        var jwt = new JwtSecurityTokenHandler().ReadJwtToken(token);
        Assert.Equal("app-issuer", jwt.Issuer);
        Assert.Contains("app-aud", jwt.Audiences);
        Assert.Contains(jwt.Claims, c => c.Type == "sub" && c.Value == "user-123");
        Assert.Contains(jwt.Claims, c => c.Type == ClaimTypes.Email && c.Value == "user@example.com");
        Assert.InRange(jwt.ValidTo, exp.AddSeconds(-5), exp.AddSeconds(5));
    }
}
