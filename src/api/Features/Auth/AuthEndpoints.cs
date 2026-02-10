namespace Api.Features.Auth;

public static class AuthEndpoints
{
    public static RouteGroupBuilder MapAuthEndpoints(this RouteGroupBuilder apiV1)
    {
        var group = apiV1.MapGroup("/auth")
            .WithTags("Auth");

        group.MapPost("/google", ExchangeGoogleIdToken.Handle)
             .AllowAnonymous();

        group.MapGet("/me", Me.Handle)
             .RequireAuthorization();

        return apiV1;
    }
}
