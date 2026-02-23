using Api.Features.Todos;
using Microsoft.EntityFrameworkCore;

namespace Api.Data;

public sealed class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<TodoItem> Todos => Set<TodoItem>();
}
