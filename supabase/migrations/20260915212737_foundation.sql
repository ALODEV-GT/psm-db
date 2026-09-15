-- Migration: foundation
-- Domain enums shared across every later table, plus the generic
-- updated_at trigger function every table with an updated_at column attaches.

create type public.user_role as enum ('admin', 'usuario', 'tecnico');

create type public.event_status as enum ('programado', 'en_curso', 'finalizado', 'cerrado');

create type public.service_type as enum (
  'transmision_en_vivo',
  'fotografias',
  'entrevistas',
  'anuncios',
  'fotos_impresas',
  'fotos_enmarcadas',
  'copia_evento'
);

create type public.livestream_visibility as enum ('publico', 'privado');

create type public.checklist_item as enum ('audio', 'video', 'conexion', 'plataforma');

-- Generic BEFORE UPDATE trigger function: stamps updated_at = now() on every row update.
-- Every table below (migrations 01+) that has an updated_at column attaches this trigger.
create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
