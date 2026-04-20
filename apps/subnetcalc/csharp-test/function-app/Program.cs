using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

Console.WriteLine("========== C# TEST FUNCTION APP STARTING ==========");

var host = new HostBuilder()
    .ConfigureFunctionsWebApplication()
    .ConfigureLogging(logging =>
    {
        Console.WriteLine("========== CONFIGURING LOGGING ==========");
        logging.AddConsole();
        logging.SetMinimumLevel(LogLevel.Information);
    })
    .Build();

Console.WriteLine("========== STARTING FUNCTION APP HOST ==========");
host.Run();
