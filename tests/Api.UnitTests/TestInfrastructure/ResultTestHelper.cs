using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;

namespace Api.UnitTests.TestInfrastructure;

internal sealed class ExecutedResult
{
    public required int StatusCode { get; init; }
    public required string Body { get; init; }
    public required IHeaderDictionary Headers { get; init; }
}

internal static class ResultTestHelper
{
    public static async Task<ExecutedResult> ExecuteAsync(IResult result)
    {
        var http = new DefaultHttpContext();
        http.Response.Body = new MemoryStream();
        http.RequestServices = CreateRequestServices();

        await result.ExecuteAsync(http);

        http.Response.Body.Position = 0;
        using var reader = new StreamReader(http.Response.Body);
        var body = await reader.ReadToEndAsync();

        return new ExecutedResult
        {
            StatusCode = http.Response.StatusCode,
            Body = body,
            Headers = http.Response.Headers
        };
    }

    public static JsonDocument ParseJson(string body) => JsonDocument.Parse(body);

    private static IServiceProvider CreateRequestServices()
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddOptions();
        services.AddProblemDetails();
        return services.BuildServiceProvider();
    }
}
