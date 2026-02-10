using System.Security.Claims;

namespace Api.Features.Auth;

public static class Me
{
    public sealed record Response(string Subject, string? Email, string? Name);

    public static IResult Handle(ClaimsPrincipal user)
    {
        var sub = user.FindFirstValue("sub") ?? user.FindFirstValue(ClaimTypes.NameIdentifier) ?? "";
        var email = user.FindFirstValue(ClaimTypes.Email);
        var name = user.FindFirstValue(ClaimTypes.Name);

        return Results.Ok(new Response(sub, email, name));
    }
}
