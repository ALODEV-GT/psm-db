-- Migration: event_secondary_phone
-- Optional secondary contact number for one event, used when the client does
-- not answer the primary phone. Per event by design: it is not stored on the
-- client, so it never leaks into other events.

alter table public.events
  add column secondary_phone_number text,
  add constraint events_secondary_phone_number_ck check (
    secondary_phone_number is null or secondary_phone_number ~ '^[0-9+()]{8,20}$'
  );
