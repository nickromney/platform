FROM mcr.microsoft.com/dotnet/sdk:9.0 AS installer-env

# Copy project file and restore
COPY *.csproj ./
RUN dotnet restore

# Copy all source code and publish
COPY . /src/dotnet-function-app
RUN cd /src/dotnet-function-app && \
    mkdir -p /home/site/wwwroot && \
    dotnet publish *.csproj --output /home/site/wwwroot

# Use .NET 9 isolated runtime
FROM mcr.microsoft.com/azure-functions/dotnet-isolated:4-dotnet-isolated9.0

ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true \
    WEBSITES_PORT=8080 \
    ASPNETCORE_URLS=http://+:8080

COPY --chown=app:app --from=installer-env ["/home/site/wwwroot", "/home/site/wwwroot"]

EXPOSE 8080

USER app
