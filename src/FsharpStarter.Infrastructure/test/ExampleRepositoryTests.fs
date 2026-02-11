module FsharpStarter.Infrastructure.Tests.ExampleRepositoryTests

open System
open Microsoft.Data.Sqlite
open Microsoft.EntityFrameworkCore
open FsharpStarter.Domain.Ports
open FsharpStarter.Domain.Entities
open FsharpStarter.Domain.ValueObjects
open FsharpStarter.Infrastructure.Database
open FsharpStarter.Infrastructure.Database.Repositories
open Xunit

[<Fact>]
let ``Repository saves events and rehydrates aggregate`` () =
    use connection = new SqliteConnection("Data Source=:memory:")
    connection.Open()

    let options =
        DbContextOptionsBuilder<FsharpStarterDbContext>().UseSqlite(connection).Options

    use dbContext = new FsharpStarterDbContext(options)
    dbContext.Database.EnsureCreated() |> ignore

    let repository = ExampleRepository(dbContext) :> IExampleRepository

    let aggregate =
        match ExampleAggregate.Create(ExampleId.New(), "Stored Example", DateTimeOffset.UtcNow) with
        | Error error -> failwithf "Expected aggregate creation success but got %A" error
        | Ok value -> value

    let saved = repository.Save(aggregate) |> Async.RunSynchronously

    match saved with
    | Error error -> failwithf "Expected save success but got %A" error
    | Ok() -> ()

    let id =
        match aggregate.State with
        | None -> failwith "Missing aggregate state"
        | Some state -> state.Id

    let loaded = repository.GetById(id) |> Async.RunSynchronously

    match loaded with
    | Error error -> failwithf "Expected load success but got %A" error
    | Ok None -> failwith "Expected aggregate to exist"
    | Ok(Some value) ->
        match value.State with
        | None -> failwith "Expected rehydrated state"
        | Some state -> Assert.Equal("Stored Example", state.Name)
