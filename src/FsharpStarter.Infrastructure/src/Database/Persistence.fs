namespace FsharpStarter.Infrastructure.Database

open System
open Microsoft.EntityFrameworkCore
open Microsoft.Extensions.DependencyInjection
open FsharpStarter.Domain.Ports
open FsharpStarter.Infrastructure.Database.Repositories

module Persistence =

    let addInfrastructure (services: IServiceCollection) (connectionString: string) =
        services.AddDbContext<FsharpStarterDbContext>(fun options -> options.UseSqlite(connectionString) |> ignore)
        |> ignore

        services.AddScoped<IExampleRepository, ExampleRepository>() |> ignore
        services

    let initializeDatabase (serviceProvider: IServiceProvider) =
        use scope = serviceProvider.CreateScope()
        let dbContext = scope.ServiceProvider.GetRequiredService<FsharpStarterDbContext>()
        dbContext.Database.EnsureCreated() |> ignore
