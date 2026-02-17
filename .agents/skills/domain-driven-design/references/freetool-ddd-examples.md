# F# DDD Examples (Freetool-Style)

## Overview
Use these examples when implementing Domain/Application/Infrastructure/API flows similar to:
- `~/workspace/freetool/src/Freetool.Domain/...`
- `~/workspace/freetool/src/Freetool.Application/...`
- `~/workspace/freetool/src/Freetool.Infrastructure/...`

The goal is strong domain modeling, explicit error flow, and transaction-safe persistence.

## 1) No Nulls in Domain, Use Option/Result

```fsharp
namespace Freetool.Domain.Users

open System

[<RequireQualifiedAccess>]
type DomainError =
    | ValidationError of string
    | NotFound of string
    | Conflict of string
    | InvalidOperation of string

type UnvalidatedUser =
    { Name: string option
      Email: string option }

type ValidatedUser =
    { Name: string
      Email: string }

module UserValidation =
    let validate (input: UnvalidatedUser) : Result<ValidatedUser, DomainError> =
        match input.Name, input.Email with
        | None, _ -> Error (DomainError.ValidationError "Name is required")
        | _, None -> Error (DomainError.ValidationError "Email is required")
        | Some name, Some email when String.IsNullOrWhiteSpace name ->
            Error (DomainError.ValidationError "Name cannot be empty")
        | Some _, Some email when String.IsNullOrWhiteSpace email ->
            Error (DomainError.ValidationError "Email cannot be empty")
        | Some name, Some email ->
            Ok { Name = name; Email = email }
```

## 2) Opaque Types for Identity and Value Objects

```fsharp
namespace Freetool.Domain.ValueObjects

open System

[<Struct>]
type AppId =
    | AppId of Guid
    static member FromGuid(id: Guid) = AppId id
    member this.Value = let (AppId value) = this in value

[<Struct>]
type UserId =
    | UserId of Guid
    static member FromGuid(id: Guid) = UserId id
    member this.Value = let (UserId value) = this in value

[<Struct>]
type Email =
    private
    | Email of string

module Email =
    let create (value: string) =
        if String.IsNullOrWhiteSpace value then
            Error (DomainError.ValidationError "Email cannot be empty")
        elif value.Contains("@") |> not then
            Error (DomainError.ValidationError "Email must contain '@'")
        else
            Ok (Email value)

    let value (Email v) = v
```

Boundary conversion in Application/API happens once:

```fsharp
match Guid.TryParse dto.AppId with
| true, guid ->
    let appId = AppId.FromGuid guid
    let! app = appRepository.GetByIdAsync appId
    // continue with typed ID only
| false, _ ->
    return Error (DomainError.ValidationError "Invalid AppId")
```

## 3) Domain Invariants Inside Aggregate Methods

```fsharp
namespace Freetool.Domain.Entities

open System
open Freetool.Domain.Users
open Freetool.Domain.ValueObjects

type User =
    { UserId: UserId
      Name: string
      Email: Email
      Version: int }

module User =
    let updateName (newName: string option) (user: User) : Result<User, DomainError> =
        match newName with
        | None -> Error (DomainError.ValidationError "User name cannot be null")
        | Some nameValue when String.IsNullOrWhiteSpace nameValue ->
            Error (DomainError.ValidationError "User name cannot be empty")
        | Some nameValue when nameValue.Length > 120 ->
            Error (DomainError.ValidationError "User name is too long")
        | Some nameValue ->
            Ok { user with Name = nameValue; Version = user.Version + 1 }
```

## 4) Explicit Domain Error Model + Result Flow

```fsharp
namespace Freetool.Domain

[<RequireQualifiedAccess>]
type DomainError =
    | ValidationError of string
    | NotFound of string
    | Conflict of string
    | InvalidOperation of string
```

Use errors through all layers:

```fsharp
let bindResult taskResult next = task {
    let! result = taskResult
    match result with
    | Ok value -> return! next value
    | Error e -> return Error e
}
```

## 5) Domain Events as First-Class Facts

```fsharp
namespace Freetool.Domain.Events

open System
open Freetool.Domain.ValueObjects

type UserCreatedEvent =
    { EventId: Guid
      OccurredAt: DateTime
      UserId: UserId
      ActorUserId: UserId
      Name: string
      Email: Email }

type UserNameUpdatedEvent =
    { EventId: Guid
      OccurredAt: DateTime
      UserId: UserId
      ActorUserId: UserId
      OldName: string
      NewName: string }
```

Aggregate emits and tracks uncommitted events:

```fsharp
type UserAggregate =
    { State: User
      UncommittedEvents: obj list }

module UserAggregate =
    let appendEvent evt agg =
        { agg with UncommittedEvents = agg.UncommittedEvents @ [ evt :> obj ] }
```

## 6) Application Layer Orchestrates Domain + Repo

```fsharp
namespace Freetool.Application.Handlers

open System
open Freetool.Domain
open Freetool.Domain.Entities
open Freetool.Domain.ValueObjects
open Freetool.Application.Interfaces

type UpdateUserNameCommand =
    { UserId: string
      ActorUserId: string
      Name: string }

type UserHandler(userRepository: IUserRepository) =

    member _.HandleUpdateName(command: UpdateUserNameCommand) = task {
        match Guid.TryParse command.UserId, Guid.TryParse command.ActorUserId with
        | (true, userGuid), (true, actorGuid) ->
            let userId = UserId.FromGuid userGuid
            let actorUserId = UserId.FromGuid actorGuid

            let! userOption = userRepository.GetByIdAsync userId
            match userOption with
            | None ->
                return Error (DomainError.NotFound "User not found")
            | Some user ->
                match User.updateName (Some command.Name) user with
                | Error domainError ->
                    return Error domainError
                | Ok updatedUser ->
                    return! userRepository.UpdateAsync actorUserId updatedUser
        | _ ->
            return Error (DomainError.ValidationError "Invalid user id")
    }
```

## 7) Repository Contract in Application, Impl in Infrastructure

Application contract:

```fsharp
namespace Freetool.Application.Interfaces

open System.Threading.Tasks
open Freetool.Domain
open Freetool.Domain.Entities
open Freetool.Domain.ValueObjects

type IUserRepository =
    abstract member GetByIdAsync: UserId -> Task<User option>
    abstract member UpdateAsync: UserId -> User -> Task<Result<unit, DomainError>>
```

Infrastructure implementation:

```fsharp
namespace Freetool.Infrastructure.Database.Repositories

open Freetool.Application.Interfaces
open Freetool.Domain
open Freetool.Domain.Entities
open Freetool.Domain.ValueObjects

type UserRepository(context: FreetoolDbContext, eventRepository: IEventRepository) =
    interface IUserRepository with
        member _.GetByIdAsync(userId: UserId) = task {
            let id = userId.Value
            let! entity = context.Users.FindAsync(id).AsTask()
            // map EF entity -> domain option
            return entity |> Option.ofObj |> Option.map UserMapper.toDomain
        }

        member _.UpdateAsync(actorUserId: UserId) (user: User) = task {
            // implementation shown in transaction section below
            return Ok ()
        }
```

## 8) Aggregate State + Events Saved Atomically

```fsharp
member _.UpdateAsync(actorUserId: UserId) (aggregate: UserAggregate) = task {
    use tx = context.Database.BeginTransaction()

    try
        let stateEntity = UserMapper.toEntity aggregate.State
        context.Users.Update(stateEntity) |> ignore

        for evt in aggregate.UncommittedEvents do
            do! eventRepository.SaveEventAsync evt

        let! _ = context.SaveChangesAsync()
        do! tx.CommitAsync()
        return Ok ()
    with ex ->
        do! tx.RollbackAsync()
        return Error (DomainError.InvalidOperation $"Failed to persist user: {ex.Message}")
}
```

## 9) DTO-Domain Mapping Layer

```fsharp
namespace Freetool.Application.Mappers

open Freetool.Domain
open Freetool.Domain.ValueObjects

type InputTypeDto =
    | Email
    | Text of int

type InputType =
    | EmailInput
    | TextInput of int

module AppMapper =
    let inputTypeFromDtoType (dto: InputTypeDto) : Result<InputType, DomainError> =
        match dto with
        | Email -> Ok EmailInput
        | Text maxLength when maxLength <= 0 ->
            Error (DomainError.ValidationError "Text maxLength must be greater than 0")
        | Text maxLength when maxLength > 2000 ->
            Error (DomainError.ValidationError "Text maxLength is too large")
        | Text maxLength ->
            Ok (TextInput maxLength)
```

## 10) Generic Command Handler Contract

```fsharp
namespace Freetool.Application.Interfaces

open System.Threading.Tasks
open Freetool.Domain

type ICommandHandler<'TCommand, 'TResult> =
    abstract member HandleCommand: 'TCommand -> Task<Result<'TResult, DomainError>>
```

Example implementation:

```fsharp
type CreateUserHandler(userRepository: IUserRepository) =
    interface ICommandHandler<CreateUserCommand, UserDto> with
        member _.HandleCommand(command) = task {
            // parse/validate -> domain call -> persist -> map result
            return Error (DomainError.InvalidOperation "Not implemented")
        }
```

## EF Core Boundaries for Null/Converters (Infrastructure Only)
Keep this out of Domain types:

```fsharp
open Microsoft.EntityFrameworkCore.Storage.ValueConversion

let emailConverter =
    ValueConverter<Email, string>(
        (fun email -> Email.value email),
        (fun value ->
            match Email.create value with
            | Ok email -> email
            | Error _ -> failwith "Invalid persisted email"
        )
    )
```

## Practical Review Prompts
- Does any Domain module depend on EF Core or ASP.NET namespaces?
- Are string IDs still flowing past API/Application boundaries?
- Can any invalid state be created without returning `Error`?
- Are events emitted consistently for state transitions?
- Is persistence atomic for state + events?
