namespace Api.Features.TestAuth;

public static class TestAuthEndpoints
{
    public static RouteGroupBuilder MapTestAuthEndpoints(this RouteGroupBuilder apiV1)
    {
        var group = apiV1.MapGroup("/test/auth")
            .WithTags("Test Auth");

        group.MapPost("/login", E2eLogin.Handle)
            .AllowAnonymous();

        return apiV1;
    }
}
