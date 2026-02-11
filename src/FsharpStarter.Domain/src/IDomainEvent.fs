namespace FsharpStarter.Domain

open System

type IDomainEvent =
    abstract member EventId: Guid
    abstract member AggregateId: Guid
    abstract member Version: int
    abstract member OccurredAt: DateTimeOffset
    abstract member EventTypeName: string
