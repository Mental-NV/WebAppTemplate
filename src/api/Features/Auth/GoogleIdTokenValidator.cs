using Google.Apis.Auth;

namespace Api.Features.Auth;

public sealed class GoogleIdTokenValidator : IGoogleIdTokenValidator
{
    public Task<GoogleJsonWebSignature.Payload> ValidateAsync(string idToken, string clientId, CancellationToken ct)
    {
        return GoogleJsonWebSignature.ValidateAsync(idToken, new GoogleJsonWebSignature.ValidationSettings
        {
            Audience = new[] { clientId }
        });
    }
}
