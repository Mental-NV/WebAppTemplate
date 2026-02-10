namespace Api.Features.Auth;

public sealed class JwtOptions
{
    public string Issuer { get; init; } = "AppTemplate";
    public string Audience { get; init; } = "AppTemplate";
    public string SigningKey { get; init; } = "";
    public int AccessTokenMinutes { get; init; } = 60;
}
