using System.ComponentModel.DataAnnotations;

namespace Api.Features.Auth;

public sealed class JwtOptions
{
    [Required]
    public string Issuer { get; init; } = "AppTemplate";

    [Required]
    public string Audience { get; init; } = "AppTemplate";

    [Required]
    [MinLength(32, ErrorMessage = "Jwt:SigningKey must be at least 32 characters.")]
    [RegularExpression(@"^(?!REPLACE_ME).+", ErrorMessage = "Jwt:SigningKey must be replaced from the template placeholder.")]
    public string SigningKey { get; init; } = "";

    [Range(1, 1440, ErrorMessage = "Jwt:AccessTokenMinutes must be between 1 and 1440.")]
    public int AccessTokenMinutes { get; init; } = 60;
}
