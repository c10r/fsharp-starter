CREATE TABLE IF NOT EXISTS examples (
    Id TEXT NOT NULL PRIMARY KEY,
    Name TEXT NOT NULL,
    CreatedAt TEXT NOT NULL,
    Version INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS domain_events (
    EventId TEXT NOT NULL PRIMARY KEY,
    AggregateId TEXT NOT NULL,
    Version INTEGER NOT NULL,
    OccurredAt TEXT NOT NULL,
    EventType TEXT NOT NULL,
    PayloadJson TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS IX_domain_events_AggregateId_Version
ON domain_events (AggregateId, Version);
