-- Options artifacts for todos (comparison / booking lists).
--
-- When a Hermes run surfaces structured choices the user should revisit —
-- flight options, hotel picks, movie showtimes, haircut slots, etc. — the
-- agent emits one `options` artifact with an `items` array. The iOS detail
-- view renders a single shared card; domains differ via payload.category.
--
-- Payload conventions (free-form jsonb; not enforced by the schema):
--   options -> {
--     "schema": "booking_option",
--     "category": "flight" | "hotel" | "event" | "movie" | "haircut" | ...,
--     "provider": "google_flights" | ...,
--     "summary": "SFO → JFK, Tue Jun 10",
--     "items": [
--       {
--         "id": "ua-815",
--         "title": "United · 8:15 AM",
--         "subtitle": "1h 32m · Nonstop",
--         "badge": "$189",
--         "url": "https://...",
--         "fields": [{ "label": "Depart", "value": "8:15 AM SFO" }]
--       }
--     ],
--     "selected_id": "ua-815"
--   }
--
-- Keep in sync with:
--   * `_ARTIFACT_KINDS` in runner/runner/events.py
--   * `ArtifactKind` in ios/doit/doit/Models/TodoArtifact.swift

alter table todo_artifacts
    drop constraint if exists todo_artifacts_kind_check;

alter table todo_artifacts
    add constraint todo_artifacts_kind_check
    check (kind in (
        'link', 'email', 'calendar', 'text', 'audio', 'image', 'options'
    ));
