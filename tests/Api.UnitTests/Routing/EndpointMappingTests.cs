using Api.Features.Auth;
using Api.Data;
using Api.Features.Todos;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.Options;

namespace Api.UnitTests.Routing;

public sealed class EndpointMappingTests
{
    [Fact]
    public void MapTodosEndpoints_MapsExpectedRoutes_AndRequiresAuthorization()
    {
        using var app = CreateApp();
        var v1 = app.MapGroup("/api/v1");

        v1.MapTodosEndpoints();

        var endpoints = ((IEndpointRouteBuilder)app).DataSources.SelectMany(x => x.Endpoints).OfType<RouteEndpoint>().ToList();

        AssertRoute(endpoints, "/api/v1/todos/", "GET", requiresAuth: true);
        AssertRoute(endpoints, "/api/v1/todos/{id:int}", "GET", requiresAuth: true);
        AssertRoute(endpoints, "/api/v1/todos/", "POST", requiresAuth: true);
        AssertRoute(endpoints, "/api/v1/todos/{id:int}", "PUT", requiresAuth: true);
        AssertRoute(endpoints, "/api/v1/todos/{id:int}", "DELETE", requiresAuth: true);
    }

    [Fact]
    public void MapAuthEndpoints_MapsGoogleAndMe_WithExpectedAuthMetadata()
    {
        using var app = CreateApp();
        var v1 = app.MapGroup("/api/v1");

        v1.MapAuthEndpoints();

        var endpoints = ((IEndpointRouteBuilder)app).DataSources.SelectMany(x => x.Endpoints).OfType<RouteEndpoint>().ToList();

        var google = FindRoute(endpoints, "/api/v1/auth/google", "POST");
        Assert.NotNull(google);
        Assert.Contains(google!.Metadata, m => m is IAllowAnonymous);

        var me = FindRoute(endpoints, "/api/v1/auth/me", "GET");
        Assert.NotNull(me);
        Assert.Contains(me!.Metadata, m => m is IAuthorizeData);
    }

    private static WebApplication CreateApp()
    {
        var builder = WebApplication.CreateBuilder();
        builder.Services.AddAuthorization();
        builder.Services.AddScoped<AppDbContext>(_ => null!);
        builder.Services.AddSingleton<IGoogleIdTokenValidator, FakeGoogleIdTokenValidator>();
        builder.Services.AddSingleton(_ => new JwtTokenService(Options.Create(new JwtOptions
        {
            Issuer = "issuer",
            Audience = "audience",
            SigningKey = new string('k', 32)
        })));
        return builder.Build();
    }

    private sealed class FakeGoogleIdTokenValidator : IGoogleIdTokenValidator
    {
        public Task<Google.Apis.Auth.GoogleJsonWebSignature.Payload> ValidateAsync(string idToken, string clientId, CancellationToken ct)
            => throw new NotImplementedException();
    }

    private static void AssertRoute(IEnumerable<RouteEndpoint> endpoints, string pattern, string method, bool requiresAuth)
    {
        var endpoint = FindRoute(endpoints, pattern, method);
        Assert.NotNull(endpoint);

        if (requiresAuth)
            Assert.Contains(endpoint!.Metadata, m => m is IAuthorizeData);
    }

    private static RouteEndpoint? FindRoute(IEnumerable<RouteEndpoint> endpoints, string pattern, string method)
    {
        return endpoints.FirstOrDefault(e =>
        {
            if (!string.Equals(e.RoutePattern.RawText, pattern, StringComparison.Ordinal))
                return false;

            var methods = e.Metadata.GetMetadata<IHttpMethodMetadata>()?.HttpMethods;
            return methods is not null && methods.Contains(method, StringComparer.OrdinalIgnoreCase);
        });
    }
}
