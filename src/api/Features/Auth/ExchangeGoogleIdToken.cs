using System.Security.Claims;
using Google.Apis.Auth;
using Microsoft.Extensions.Options;

namespace Api.Features.Auth;

public static class ExchangeGoogleIdToken
{
    public sealed record Request(string IdToken);
    public sealed record UserDto(string Subject, string? Email, string? Name, string? PictureUrl);
    public sealed record Response(string AccessToken, DateTime ExpiresAtUtc, UserDto User);

    public static async Task<IResult> Handle(
        Request req,
        IOptions<GoogleOptions> googleOptions,
        IGoogleIdTokenValidator googleIdTokenValidator,
        JwtTokenService jwt,
        IWebHostEnvironment env,
        CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(req.IdToken))
            return Results.BadRequest(new { error = "idToken is required" });

        var clientId = googleOptions.Value.ClientId;
        if (string.IsNullOrWhiteSpace(clientId))
            return Results.Problem("Google:ClientId is not configured.", statusCode: 500);
        if (clientId.Contains("REPLACE_ME", StringComparison.OrdinalIgnoreCase))
            return Results.Problem("Google:ClientId is still set to the placeholder value.", statusCode: 500);

        GoogleJsonWebSignature.Payload payload;
        try
        {
            payload = await googleIdTokenValidator.ValidateAsync(req.IdToken, clientId, ct);
        }
        catch (Exception ex)
        {
            if (env.IsDevelopment())
            {
                return Results.Json(new
                {
                    error = "Invalid Google ID token",
                    detail = ex.Message
                }, statusCode: 401);
            }

            return Results.Unauthorized();
        }

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, payload.Subject),
            new("sub", payload.Subject),
        };

        if (!string.IsNullOrWhiteSpace(payload.Email))
            claims.Add(new Claim(ClaimTypes.Email, payload.Email));

        if (!string.IsNullOrWhiteSpace(payload.Name))
            claims.Add(new Claim(ClaimTypes.Name, payload.Name));

        var (token, exp) = jwt.CreateAccessToken(claims);

        var user = new UserDto(payload.Subject, payload.Email, payload.Name, payload.Picture);
        return Results.Ok(new Response(token, exp, user));
    }
}
