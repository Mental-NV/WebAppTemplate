namespace Api.Features.TestAuth;

public sealed class E2eAuthOptions
{
    public bool Enabled { get; init; }
    public string Secret { get; init; } = "";
}
