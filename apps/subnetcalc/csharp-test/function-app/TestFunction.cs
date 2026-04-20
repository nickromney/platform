using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using System.Net;
using System.Text.Json;

namespace TestFunction;

public class TestFunction(ILogger<TestFunction> logger)
{
    [Function("Test")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "test")] HttpRequestData request)
    {
        logger.LogInformation("========== TEST FUNCTION CALLED ==========");
        logger.LogInformation("Request Path: {Path}", request.Url.PathAndQuery);
        logger.LogInformation("Request Headers: {Headers}", string.Join(", ", request.Headers.Select(h => $"{h.Key}={string.Join(",", h.Value)}")));

        var response = request.CreateResponse(HttpStatusCode.OK);
        response.Headers.Add("Content-Type", "application/json");

        var result = new
        {
            message = "C# Test Function Works!",
            timestamp = DateTime.UtcNow,
            requestPath = request.Url.PathAndQuery,
            headers = request.Headers.ToDictionary(h => h.Key, h => string.Join(",", h.Value))
        };

        var json = JsonSerializer.Serialize(result, new JsonSerializerOptions { WriteIndented = true });
        logger.LogInformation("Returning response: {Response}", json);

        await response.WriteStringAsync(json);
        return response;
    }

    [Function("Health")]
    public async Task<HttpResponseData> Health(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "health")] HttpRequestData request)
    {
        logger.LogInformation("Health check requested");

        var response = request.CreateResponse(HttpStatusCode.OK);
        response.Headers.Add("Content-Type", "application/json");

        await response.WriteStringAsync(JsonSerializer.Serialize(new
        {
            status = "healthy",
            timestamp = DateTime.UtcNow
        }));

        return response;
    }
}
