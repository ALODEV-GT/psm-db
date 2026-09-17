-- pgTAP test: migration 00_foundation
-- Asserts the 5 domain enums and the set_updated_at() trigger function exist.

begin;

select plan(12);

-- Enums exist with the exact PRD-derived label sets (design.md "Enums (migration 00)")

select has_type('public', 'user_role', 'user_role enum exists');
select enum_has_labels(
  'public', 'user_role',
  array['admin', 'usuario', 'tecnico'],
  'user_role has the expected labels'
);

select has_type('public', 'event_status', 'event_status enum exists');
select enum_has_labels(
  'public', 'event_status',
  array['programado', 'en_curso', 'finalizado', 'cerrado'],
  'event_status has the expected labels'
);

select has_type('public', 'service_type', 'service_type enum exists');
select enum_has_labels(
  'public', 'service_type',
  array[
    'transmision_en_vivo', 'fotografias', 'entrevistas', 'anuncios',
    'fotos_impresas', 'fotos_enmarcadas', 'copia_evento'
  ],
  'service_type has the expected labels'
);

select has_type('public', 'livestream_visibility', 'livestream_visibility enum exists');
select enum_has_labels(
  'public', 'livestream_visibility',
  array['publico', 'privado'],
  'livestream_visibility has the expected labels'
);

select has_type('public', 'checklist_item', 'checklist_item enum exists');
select enum_has_labels(
  'public', 'checklist_item',
  array['audio', 'video', 'conexion', 'plataforma'],
  'checklist_item has the expected labels'
);

-- Shared trigger function used by every later table's updated_at column

select has_function('public', 'set_updated_at', 'set_updated_at() function exists');
select function_returns('public', 'set_updated_at', 'trigger', 'set_updated_at() returns trigger');

select * from finish();

rollback;
