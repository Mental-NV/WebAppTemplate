using System.ComponentModel.DataAnnotations;

namespace Api.Features.Auth;

public sealed class GoogleOptions
{
    [Required]
    [RegularExpression(@".+\.apps\.googleusercontent\.com$", ErrorMessage = "Google:ClientId must be a valid Google OAuth Web client ID.")]
    public string ClientId { get; init; } = "";
}
