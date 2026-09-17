// Domain seed helpers for scripts/seed-dev-data.mjs — everything that
// inserts sample clients/events/services and their children, downstream of
// the admin-API user creation (design.md D1/D2). Split out of
// seed-dev-data.mjs to keep that file focused on credential resolution and
// the loopback guard (code-style soft file-length limit).

export const DEV_PASSWORD = "DevPassword123";

export const USERS = [
  { key: "admin", email: "admin@proyecto1.test", fullName: "Admin Demo", role: "admin" },
  { key: "usuario", email: "usuario@proyecto1.test", fullName: "Usuario Demo", role: "usuario" },
  { key: "tecnico", email: "tecnico@proyecto1.test", fullName: "Tecnico Demo", role: "tecnico" },
];

export async function createUsers(supabase) {
  const profileIds = {};
  for (const user of USERS) {
    const { data, error } = await supabase.auth.admin.createUser({
      email: user.email,
      password: DEV_PASSWORD,
      email_confirm: true,
      user_metadata: { full_name: user.fullName },
    });
    if (error) throw error;
    profileIds[user.key] = data.user.id;

    // handle_new_user() always inserts role='usuario' (design.md D3); the
    // seed script backfills admin/tecnico as an ordinary authenticated write.
    if (user.role !== "usuario") {
      const { error: updateError } = await supabase
        .from("profiles")
        .update({ role: user.role })
        .eq("id", data.user.id);
      if (updateError) throw updateError;
    }
  }
  return profileIds;
}

export async function fetchLookupId(supabase, table, name) {
  const { data, error } = await supabase
    .from(table)
    .select("id")
    .eq("name", name)
    .single();
  if (error) throw error;
  return data.id;
}

export async function seedClients(supabase, adminId) {
  const { data, error } = await supabase
    .from("clients")
    .insert([
      {
        name: "Familia Ramírez",
        department: "Guatemala",
        municipality: "Guatemala",
        address: "5ta avenida 10-25 zona 1",
        phone: "+502 5555 1234",
        email: "ramirez.familia@example.com",
        created_by: adminId,
      },
      {
        name: "Familia García",
        department: "Guatemala",
        municipality: "Mixco",
        address: "3ra calle 4-56 zona 2",
        phone: "+502 5555 9876",
        email: "garcia.familia@example.com",
        created_by: adminId,
      },
    ])
    .select("id, name");
  if (error) throw error;
  return {
    ramirezId: data.find((row) => row.name === "Familia Ramírez").id,
    garciaId: data.find((row) => row.name === "Familia García").id,
  };
}

export async function seedOpenEvent(supabase, { adminId, tecnicoId, usuarioId, clientId, eventTypeId }) {
  const { data: event, error: eventError } = await supabase
    .from("events")
    .insert({
      client_id: clientId,
      event_type_id: eventTypeId,
      location: "Salón Los Álamos, zona 10, Guatemala",
      notes: "Evento de muestra generado por el seed de desarrollo.",
      deposit_amount: 1500,
      status: "programado",
      title: "Boda Ramírez",
      created_by: adminId,
    })
    .select("id")
    .single();
  if (eventError) throw eventError;
  const eventId = event.id;

  const { data: livestreamService, error: livestreamError } = await supabase
    .from("event_services")
    .insert({
      event_id: eventId,
      service_type: "transmision_en_vivo",
      service_date: "2026-11-14",
      start_time: "16:00",
      end_time: "20:00",
      price_per_hour: 350,
      visibility: "privado",
      stream_title: "Boda de Ana y Luis",
      stream_description: "Transmisión privada para familiares y amigos.",
    })
    .select("id")
    .single();
  if (livestreamError) throw livestreamError;

  const { error: unitServiceError } = await supabase.from("event_services").insert({
    event_id: eventId,
    service_type: "fotos_impresas",
    price_per_unit: 25,
    quantity: 40,
  });
  if (unitServiceError) throw unitServiceError;

  const [facebookId, youtubeId] = await Promise.all([
    fetchLookupId(supabase, "platforms", "Facebook"),
    fetchLookupId(supabase, "platforms", "YouTube"),
  ]);

  // service_type is omitted on both child tables — the D10 default fills it
  // in and the composite FK certifies the parent is a livestream row.
  const { error: platformsError } = await supabase.from("event_service_platforms").insert([
    { event_service_id: livestreamService.id, platform_id: facebookId },
    { event_service_id: livestreamService.id, platform_id: youtubeId },
  ]);
  if (platformsError) throw platformsError;

  const { error: phoneNumbersError } = await supabase.from("livestream_phone_numbers").insert([
    { event_service_id: livestreamService.id, phone_number: "+502 5555 1234" },
    { event_service_id: livestreamService.id, phone_number: "+502 5555 5678" },
  ]);
  if (phoneNumbersError) throw phoneNumbersError;

  const { error: checklistError } = await supabase.from("event_checklist").insert([
    { event_id: eventId, item: "audio", is_completed: true, completed_at: new Date().toISOString(), completed_by: tecnicoId },
    { event_id: eventId, item: "video", is_completed: true, completed_at: new Date().toISOString(), completed_by: tecnicoId },
    { event_id: eventId, item: "conexion", is_completed: false },
    { event_id: eventId, item: "plataforma", is_completed: false },
  ]);
  if (checklistError) throw checklistError;

  const { error: timelineError } = await supabase.from("timeline_notes").insert([
    { event_id: eventId, body: "Equipo de audio y video instalado.", elapsed_seconds: 0, created_by: tecnicoId },
    { event_id: eventId, body: "Inicia la ceremonia.", elapsed_seconds: 1800, created_by: usuarioId },
  ]);
  if (timelineError) throw timelineError;

  const { error: staffError } = await supabase.from("event_staff").insert([
    { event_id: eventId, profile_id: tecnicoId },
    { event_id: eventId, profile_id: usuarioId },
  ]);
  if (staffError) throw staffError;

  return eventId;
}

export async function seedClosedEvent(supabase, { adminId, clientId, eventTypeId }) {
  const { data: event, error: eventError } = await supabase
    .from("events")
    .insert({
      client_id: clientId,
      event_type_id: eventTypeId,
      location: "Salón Jardines del Recuerdo, zona 15, Guatemala",
      deposit_amount: 500,
      status: "cerrado",
      title: "Cumpleaños García",
      created_by: adminId,
    })
    .select("id")
    .single();
  if (eventError) throw eventError;
  const eventId = event.id;

  // price_per_unit(200) * quantity(10) = 2000.00 services_total.
  const { error: serviceError } = await supabase.from("event_services").insert({
    event_id: eventId,
    service_type: "fotos_enmarcadas",
    price_per_unit: 200,
    quantity: 10,
  });
  if (serviceError) throw serviceError;

  const { error: expenseError } = await supabase.from("event_expenses").insert({
    event_id: eventId,
    profile_id: adminId,
    concept: "Renta de equipo adicional",
    amount: 300,
    incurred_on: "2026-09-01",
  });
  if (expenseError) throw expenseError;

  const { error: collaboratorError } = await supabase.from("event_collaborators").insert({
    event_id: eventId,
    profile_id: null,
    display_name: "Fotógrafo invitado",
    payment_amount: 250,
  });
  if (collaboratorError) throw collaboratorError;

  const servicesTotal = 2000;
  const expensesTotal = 300;
  const paymentsTotal = 250;
  const depositAmount = 500;

  const { error: closureError } = await supabase.from("event_closures").insert({
    event_id: eventId,
    services_total: servicesTotal,
    expenses_total: expensesTotal,
    payments_total: paymentsTotal,
    deposit_amount: depositAmount,
    remaining_balance: servicesTotal - depositAmount,
    closed_by: adminId,
  });
  if (closureError) throw closureError;

  return eventId;
}
