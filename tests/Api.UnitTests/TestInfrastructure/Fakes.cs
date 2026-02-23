using Google.Apis.Auth;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.FileProviders;

namespace Api.UnitTests.TestInfrastructure;

internal sealed class FakeGoogleIdTokenValidator : Api.Features.Auth.IGoogleIdTokenValidator
{
    public string? LastIdToken { get; private set; }
    public string? LastClientId { get; private set; }

    public GoogleJsonWebSignature.Payload? PayloadToReturn { get; set; }
    public Exception? ExceptionToThrow { get; set; }

    public Task<GoogleJsonWebSignature.Payload> ValidateAsync(string idToken, string clientId, CancellationToken ct)
    {
        LastIdToken = idToken;
        LastClientId = clientId;

        if (ExceptionToThrow is not null)
            throw ExceptionToThrow;

        if (PayloadToReturn is null)
            throw new InvalidOperationException("PayloadToReturn was not configured.");

        return Task.FromResult(PayloadToReturn);
    }
}

internal sealed class FakeWebHostEnvironment : IWebHostEnvironment
{
    public string EnvironmentName { get; set; } = Environments.Production;
    public string ApplicationName { get; set; } = "Api.UnitTests";
    public string WebRootPath { get; set; } = "";
    public IFileProvider WebRootFileProvider { get; set; } = new NullFileProvider();
    public string ContentRootPath { get; set; } = AppContext.BaseDirectory;
    public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
}
