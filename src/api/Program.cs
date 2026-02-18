using System.Text;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi;
using Api.Data;
using Api.Features.Auth;
using Api.Features.Todos;

var builder = WebApplication.CreateBuilder(args);

// --- Options ---
builder.Services.Configure<GoogleOptions>(builder.Configuration.GetSection("Google"));
builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection("Jwt"));
builder.Services.AddSingleton<JwtTokenService>();

// --- DB ---
builder.Services.AddDbContext<AppDbContext>(opt =>
{
    var cs = builder.Configuration.GetConnectionString("Default") ?? "Data Source=app.db";
    opt.UseSqlite(cs);
});

// --- CORS (dev) ---
builder.Services.AddCors(opt =>
{
    opt.AddPolicy("dev", p =>
        p.WithOrigins("http://localhost:5173")
         .AllowAnyHeader()
         .AllowAnyMethod());
});

// --- AuthN/AuthZ (app-issued JWT) ---
var jwtOpt = builder.Configuration.GetSection("Jwt").Get<JwtOptions>() ?? new JwtOptions();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateIssuerSigningKey = true,
            ValidateLifetime = true,
            ValidIssuer = jwtOpt.Issuer,
            ValidAudience = jwtOpt.Audience,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtOpt.SigningKey ?? "")),
            ClockSkew = TimeSpan.FromMinutes(1)
        };
    });

builder.Services.AddAuthorization();

// --- Swagger (Swashbuckle v10 / OpenAPI.NET v2) ---
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.AddSecurityDefinition("bearer", new OpenApiSecurityScheme
    {
        Type = SecuritySchemeType.Http,
        Scheme = "bearer",
        BearerFormat = "JWT",
        Description = "JWT Authorization header using the Bearer scheme."
    });

    // New in Swashbuckle v10: security requirement uses OpenApiSecuritySchemeReference
    options.AddSecurityRequirement(document => new OpenApiSecurityRequirement
    {
        [new OpenApiSecuritySchemeReference("bearer", document)] = []
    });

    options.CustomSchemaIds(t => (t.FullName ?? t.Name).Replace("+", "."));
});

var app = builder.Build();

app.UseStaticFiles();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
    app.UseCors("dev");

    await DbInitializer.InitializeAsync(app);
}

app.UseAuthentication();
app.UseAuthorization();

// Serve SPA for root and unknown routes (fallback)
app.MapFallbackToFile("index.html");

// ---- Manual URL versioning ----
// Map explicit route groups for each version.
// Add v2 later by mapping another group: /api/v2
var v1 = app.MapGroup("/api/v1");

v1.MapAuthEndpoints();
v1.MapTodosEndpoints();

app.Run();

public partial class Program { }
