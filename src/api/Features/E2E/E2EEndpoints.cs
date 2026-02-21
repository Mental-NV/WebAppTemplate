using System.Security.Claims;
using Api.Data;
using Api.Features.Auth;
using Microsoft.EntityFrameworkCore;

namespace Api.Features.E2E;

public static class E2EEndpoints
{
    public static RouteGroupBuilder MapE2EEndpoints(this RouteGroupBuilder apiV1)
    {
        var group = apiV1.MapGroup("/e2e")
            .WithTags("E2E");

        group.MapPost("/auth/login", IssueTestToken.Handle)
            .AllowAnonymous();

        group.MapPost("/reset", ResetState.Handle)
            .AllowAnonymous();

        return apiV1;
    }
}

public static class IssueTestToken
{
    public sealed record Request(string? Subject, string? Email, string? Name);
    public sealed record UserDto(string Subject, string? Email, string? Name, string? PictureUrl);
    public sealed record Response(string AccessToken, DateTime ExpiresAtUtc, UserDto User);

    public static IResult Handle(Request? req, JwtTokenService jwt)
    {
        var subject = string.IsNullOrWhiteSpace(req?.Subject) ? "e2e-subject" : req!.Subject.Trim();
        var email = string.IsNullOrWhiteSpace(req?.Email) ? "e2e@example.com" : req!.Email.Trim();
        var name = string.IsNullOrWhiteSpace(req?.Name) ? "E2E User" : req!.Name.Trim();

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, subject),
            new("sub", subject),
            new(ClaimTypes.Email, email),
            new(ClaimTypes.Name, name)
        };

        var (token, exp) = jwt.CreateAccessToken(claims);
        var user = new UserDto(subject, email, name, null);

        return Results.Ok(new Response(token, exp, user));
    }
}

public static class ResetState
{
    public static async Task<IResult> Handle(AppDbContext db, CancellationToken ct)
    {
        await db.Database.EnsureCreatedAsync(ct);
        await db.Todos.ExecuteDeleteAsync(ct);

        return Results.NoContent();
    }
}
