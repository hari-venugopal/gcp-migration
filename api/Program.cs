using Microsoft.EntityFrameworkCore;

var builder = WebApplication.CreateBuilder(args);

// Cloud Run tells the container which port to listen on.
var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";
builder.WebHost.UseUrls($"http://0.0.0.0:{port}");

// Structured JSON logs, so Cloud Logging can index the fields.
builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole();

// Config and secrets are read once at startup. On Cloud Run, DB_PASSWORD is
// injected from Secret Manager; a new revision picks up a rotated secret.
var connectionString =
    $"Host={Env("DB_HOST", "localhost")};Port=5432;Database={Env("DB_NAME", "items")};" +
    $"Username={Env("DB_USER", "postgres")};Password={Env("DB_PASSWORD", "postgres")};" +
    $"SSL Mode={Env("DB_SSL_MODE", "Prefer")}";

builder.Services.AddDbContext<AppDb>(o => o.UseNpgsql(connectionString));

var app = builder.Build();

await EnsureDatabaseAsync(app);

var version = Env("APP_VERSION", "local");   // set by the pipeline (git SHA)
var revision = Env("K_REVISION", "local");   // set by Cloud Run

var api = app.MapGroup("/api");

api.MapGet("/health", () => Results.Ok(new { status = "ok", version, revision }));

api.MapGet("/items", async (AppDb db) =>
    await db.Items.OrderByDescending(i => i.Id).Take(100).ToListAsync());

api.MapPost("/items", async (NewItem input, AppDb db) =>
{
    if (string.IsNullOrWhiteSpace(input.Name) || input.Name.Length > 200)
        return Results.BadRequest(new { error = "name is required (max 200 characters)" });

    var item = new Item { Name = input.Name.Trim(), CreatedAt = DateTime.UtcNow };
    db.Items.Add(item);
    await db.SaveChangesAsync();
    return Results.Created($"/api/items/{item.Id}", item);
});

api.MapDelete("/items/{id:int}", async (int id, AppDb db) =>
{
    var deleted = await db.Items.Where(i => i.Id == id).ExecuteDeleteAsync();
    return deleted == 0 ? Results.NotFound() : Results.NoContent();
});

app.Run();

static string Env(string key, string fallback) =>
    Environment.GetEnvironmentVariable(key) is { Length: > 0 } value ? value : fallback;

// Lab shortcut: create the table on startup. A real service would use migrations
// that are backward compatible (expand first, contract later) so rollback stays safe.
static async Task EnsureDatabaseAsync(WebApplication app)
{
    for (var attempt = 1; attempt <= 5; attempt++)
    {
        try
        {
            using var scope = app.Services.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDb>();
            await db.Database.EnsureCreatedAsync();
            return;
        }
        catch (Exception ex)
        {
            app.Logger.LogWarning(ex, "Database not ready (attempt {Attempt} of 5)", attempt);
            await Task.Delay(TimeSpan.FromSeconds(2 * attempt));
        }
    }
    app.Logger.LogError("Database unavailable; starting anyway so /api/health still responds.");
}

public class AppDb(DbContextOptions<AppDb> options) : DbContext(options)
{
    public DbSet<Item> Items => Set<Item>();
}

public class Item
{
    public int Id { get; set; }
    public string Name { get; set; } = "";
    public DateTime CreatedAt { get; set; }
}

public record NewItem(string Name);
