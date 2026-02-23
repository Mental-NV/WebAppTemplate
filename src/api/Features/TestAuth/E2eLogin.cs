using System.Security.Claims;
using Api.Features.Auth;

namespace Api.Features.TestAuth;

public static class E2eLogin
{
    internal const string SecretHeaderName = "X-E2E-Auth-Secret";

    public sealed record Request(string? Subject, string? Email, string? Name);
    public sealed record UserDto(string Subject, string? Email, string? Name);
    public sealed record Response(string AccessToken, DateTime ExpiresAtUtc, UserDto User);

    public static IResult Handle(
        Request? req,
        HttpContext http,
        IConfiguration configuration,
        JwtTokenService jwt,
        CancellationToken ct)
    {
        _ = ct;

        var options = ReadOptions(configuration);
        if (!options.Enabled)
        {
            return Results.NotFound();
        }

        if (!http.Request.Headers.TryGetValue(SecretHeaderName, out var providedSecret) ||
            string.IsNullOrWhiteSpace(options.Secret) ||
            !string.Equals(providedSecret.ToString(), options.Secret, StringComparison.Ordinal))
        {
            return Results.Json(new { error = "Forbidden" }, statusCode: StatusCodes.Status403Forbidden);
        }

        var subject = string.IsNullOrWhiteSpace(req?.Subject) ? "e2e-sub" : req.Subject.Trim();
        var email = string.IsNullOrWhiteSpace(req?.Email) ? "e2e@example.test" : req.Email.Trim();
        var name = string.IsNullOrWhiteSpace(req?.Name) ? "E2E User" : req.Name.Trim();

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, subject),
            new("sub", subject)
        };

        if (!string.IsNullOrWhiteSpace(email))
        {
            claims.Add(new Claim(ClaimTypes.Email, email));
        }

        if (!string.IsNullOrWhiteSpace(name))
        {
            claims.Add(new Claim(ClaimTypes.Name, name));
        }

        var (token, exp) = jwt.CreateAccessToken(claims);

        return Results.Ok(new Response(token, exp, new UserDto(subject, email, name)));
    }

    internal static E2eAuthOptions ReadOptions(IConfiguration configuration)
    {
        var enabledRaw = configuration["E2E_AUTH_ENABLED"];
        var enabled = bool.TryParse(enabledRaw, out var parsed) && parsed;

        return new E2eAuthOptions
        {
            Enabled = enabled,
            Secret = configuration["E2E_AUTH_SECRET"]?.Trim() ?? ""
        };
    }
}
