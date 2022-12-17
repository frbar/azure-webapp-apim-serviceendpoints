using Microsoft.AspNetCore.Mvc;

namespace Frbar.AzurePoc.BackendApi.Controllers;

[ApiController]
[Route("/api/ping")]
public class PingController : ControllerBase
{
    private readonly ILogger<PingController> _logger;

    public PingController(ILogger<PingController> logger)
    {
        _logger = logger;
    }

    [HttpGet]
    public async Task<string> Ping()
    {
        var url = Environment.GetEnvironmentVariable("URL_TO_PING");
        var config = Environment.GetEnvironmentVariable("CONFIGURATION");

        using var client = new HttpClient();
        var content = await client.GetStringAsync(url);

        return $"{config} -> {content}";
    }
}
