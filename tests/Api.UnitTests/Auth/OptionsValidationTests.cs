using System.ComponentModel.DataAnnotations;
using Api.Features.Auth;

namespace Api.UnitTests.Auth;

public sealed class OptionsValidationTests
{
    [Fact]
    public void JwtOptions_ValidConfiguration_PassesValidation()
    {
        var options = new JwtOptions
        {
            Issuer = "issuer",
            Audience = "audience",
            SigningKey = new string('s', 32),
            AccessTokenMinutes = 60
        };

        var results = Validate(options);

        Assert.Empty(results);
    }

    [Fact]
    public void JwtOptions_ShortSigningKey_FailsValidation()
    {
        var results = Validate(new JwtOptions
        {
            Issuer = "issuer",
            Audience = "audience",
            SigningKey = "short",
            AccessTokenMinutes = 60
        });

        Assert.Contains(results, r => r.ErrorMessage!.Contains("at least 32 characters", StringComparison.Ordinal));
    }

    [Fact]
    public void JwtOptions_PlaceholderSigningKey_FailsValidation()
    {
        var results = Validate(new JwtOptions
        {
            Issuer = "issuer",
            Audience = "audience",
            SigningKey = "REPLACE_ME_with_real_signing_key_12345",
            AccessTokenMinutes = 60
        });

        Assert.Contains(results, r => r.ErrorMessage!.Contains("placeholder", StringComparison.OrdinalIgnoreCase));
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1441)]
    public void JwtOptions_AccessTokenMinutes_OutOfRange_FailsValidation(int minutes)
    {
        var results = Validate(new JwtOptions
        {
            Issuer = "issuer",
            Audience = "audience",
            SigningKey = new string('s', 32),
            AccessTokenMinutes = minutes
        });

        Assert.Contains(results, r => r.ErrorMessage!.Contains("between 1 and 1440", StringComparison.Ordinal));
    }

    [Fact]
    public void GoogleOptions_InvalidClientId_FailsValidation()
    {
        var results = Validate(new GoogleOptions
        {
            ClientId = "not-a-google-client-id"
        });

        Assert.Contains(results, r => r.ErrorMessage!.Contains("valid Google OAuth Web client ID", StringComparison.Ordinal));
    }

    [Fact]
    public void GoogleOptions_ValidClientId_PassesValidation()
    {
        var results = Validate(new GoogleOptions
        {
            ClientId = "abc123.apps.googleusercontent.com"
        });

        Assert.Empty(results);
    }

    private static List<ValidationResult> Validate(object instance)
    {
        var results = new List<ValidationResult>();
        Validator.TryValidateObject(instance, new ValidationContext(instance), results, validateAllProperties: true);
        return results;
    }
}
