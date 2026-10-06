-- Migration: client_similarity_extension
-- Trigram similarity powers the non-blocking duplicate hint on client creation
-- (GET /clients/similar). Enabled here, not in the API, so the index can be
-- added later without an application change.

create extension if not exists pg_trgm;
