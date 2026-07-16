-- Extend agent_model_settings for self-hosted providers.
--
-- The agent_model_provider enum limited providers to 'openai' | 'anthropic' | 'openrouter'.
-- Self-hosted Hermes users may use any provider (e.g. opencode-go). This migration:
--   1. Changes the provider column to plain text so any provider string is accepted.
--   2. Adds a base_url column so self-hosted users can point to custom API endpoints.
--   3. Drops the now-unused enum type.

alter table agent_model_settings
    alter column provider type text using provider::text;

alter table agent_model_settings
    add column base_url text;

drop type if exists agent_model_provider;
