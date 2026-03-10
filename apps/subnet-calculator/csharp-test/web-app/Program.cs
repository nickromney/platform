using Azure.Core;
using Azure.Identity;
using System.Net.Http.Headers;

Console.WriteLine("========== C# TEST WEB APP STARTING ==========");

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddHttpClient();
builder.Logging.AddConsole();
builder.Logging.SetMinimumLevel(LogLevel.Information);

var app = builder.Build();
var logger = app.Logger;

Console.WriteLine("========== WEB APP CONFIGURED ==========");

// Read configuration
var functionAppUrl = Environment.GetEnvironmentVariable("FUNCTION_APP_URL") ?? "http://localhost:7071";
var functionAppClientId = Environment.GetEnvironmentVariable("FUNCTION_APP_CLIENT_ID");
var functionAppAudience = Environment.GetEnvironmentVariable("FUNCTION_APP_AUDIENCE");
var functionAppScope = Environment.GetEnvironmentVariable("FUNCTION_APP_SCOPE");

string? ResolveScope()
{
    if (!string.IsNullOrWhiteSpace(functionAppScope))
    {
        return functionAppScope;
    }

    if (!string.IsNullOrWhiteSpace(functionAppAudience))
    {
        return $"{functionAppAudience.TrimEnd('/')}/.default";
    }

    if (!string.IsNullOrWhiteSpace(functionAppClientId))
    {
        return $"api://{functionAppClientId}/.default";
    }

    return null;
}

var resolvedScope = ResolveScope();
var useManagedIdentity = !string.IsNullOrEmpty(resolvedScope);

Console.WriteLine($"Function App URL: {functionAppUrl}");
Console.WriteLine($"Use Managed Identity: {useManagedIdentity}");
Console.WriteLine($"Function App Scope: {(resolvedScope ?? "(not set)")}");

app.MapGet("/", () => new
{
    message = "C# Test Web App",
    endpoints = new[] { "/", "/test", "/health" },
    config = new
    {
        functionAppUrl,
        useManagedIdentity,
        functionAppScope = resolvedScope
    }
});

app.MapGet("/health", () => new
{
    status = "healthy",
    timestamp = DateTime.UtcNow
});

app.MapGet("/test", async (HttpClient httpClient, ILogger<Program> logger) =>
{
    logger.LogInformation("========== /test ENDPOINT CALLED ==========");
    logger.LogInformation("Function App URL: {Url}", functionAppUrl);
    logger.LogInformation("Use Managed Identity: {UseMI}", useManagedIdentity);

    try
    {
        var functionUrl = $"{functionAppUrl}/api/test";
        var request = new HttpRequestMessage(HttpMethod.Get, functionUrl);

        // If Managed Identity is configured, get a token
        if (useManagedIdentity)
        {
            logger.LogInformation("Getting Managed Identity token...");
            if (string.IsNullOrEmpty(resolvedScope))
            {
                logger.LogWarning("Managed Identity scope not configured, skipping token acquisition.");
            }
            else
            {
                logger.LogInformation("Using scope: {Scope}", resolvedScope);
                var credential = new DefaultAzureCredential();
                var tokenResponse = await credential.GetTokenAsync(new TokenRequestContext(new[] { resolvedScope }));
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", tokenResponse.Token);
                logger.LogInformation("Token acquired successfully for scope: {Scope}", resolvedScope);
            }
        }
        else
        {
            logger.LogInformation("No authentication - calling Function App directly");
        }

        logger.LogInformation("Calling Function App at: {Url}", functionUrl);
        var response = await httpClient.SendAsync(request);
        var content = await response.Content.ReadAsStringAsync();

        logger.LogInformation("Response Status: {Status}", response.StatusCode);

        return Results.Ok(new
        {
            proxyWorked = true,
            functionUrl,
            statusCode = (int)response.StatusCode,
            functionResponse = content,
            usedManagedIdentity = useManagedIdentity
        });
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Error calling Function App");
        return Results.Problem(new
        {
            error = ex.Message,
            type = ex.GetType().Name,
            stackTrace = ex.StackTrace
        }.ToString() ?? "Unknown error");
    }
});

Console.WriteLine("========== STARTING WEB APP HOST ==========");
app.Run();
