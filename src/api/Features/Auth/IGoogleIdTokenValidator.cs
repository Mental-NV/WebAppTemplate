using Google.Apis.Auth;

namespace Api.Features.Auth;

public interface IGoogleIdTokenValidator
{
    Task<GoogleJsonWebSignature.Payload> ValidateAsync(string idToken, string clientId, CancellationToken ct);
}
