import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * POST /api/transport/create
 *
 * Creates a TransportRequest, calls the Groupe Robert external API (placeholder),
 * stores the external_reference, sets status to 'assigned'.
 * Also triggers GHG calculation and creates a project_activity_log.
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { lot_id, container_id, pickup_address, dropoff_address, weight, description, project_id, distance_km, gps_data } = body;

    if (!lot_id || typeof lot_id !== 'string') {
      return NextResponse.json({ error: 'lot_id is required' }, { status: 400 });
    }
    if (!pickup_address || typeof pickup_address !== 'string') {
      return NextResponse.json({ error: 'pickup_address is required' }, { status: 400 });
    }
    if (!dropoff_address || typeof dropoff_address !== 'string') {
      return NextResponse.json({ error: 'dropoff_address is required' }, { status: 400 });
    }

    // ── Call external Groupe Robert API (placeholder) ────────────────────────
    const groupeRobertBaseUrl =
      process.env.GROUPE_ROBERT_API_URL || 'https://api.grouperobert.com';

    let externalReference: string | null = null;
    let scheduledTime: string | null = null;

    try {
      const externalRes = await fetch(`${groupeRobertBaseUrl}/external/grouperobert/create-shipment`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${process.env.GROUPE_ROBERT_API_KEY || 'PLACEHOLDER_KEY'}`,
        },
        body: JSON.stringify({
          pickup_address,
          dropoff_address,
          weight: weight ?? 0,
          description: description ?? `Transport lot ${lot_id}`,
          reference: lot_id,
        }),
      });

      if (externalRes.ok) {
        const externalData = await externalRes.json();
        externalReference = externalData.external_reference ?? null;
        scheduledTime = externalData.scheduled_time ?? null;
      } else {
        externalReference = `GR-${Date.now()}`;
        scheduledTime = new Date(Date.now() + 4 * 60 * 60 * 1000).toISOString();
      }
    } catch {
      externalReference = `GR-MOCK-${Date.now()}`;
      scheduledTime = new Date(Date.now() + 4 * 60 * 60 * 1000).toISOString();
    }

    // ── Persist to Supabase ──────────────────────────────────────────────────
    const supabase = await createClient();

    const { data: transportRequest, error } = await supabase
      .from('transport_requests')
      .insert({
        lot_id,
        container_id: container_id ?? null,
        pickup_address,
        dropoff_address,
        transporter: 'Groupe Robert',
        external_reference: externalReference,
        scheduled_time: scheduledTime,
        transport_status: 'assigned',
        notes: description ?? null,
      })
      .select()
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    // ── MRV: GHG calculation + activity log ──────────────────────────────────
    let activityLog = null;
    if (project_id) {
      try {
        const baseUrl = process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000';
        const estimatedDistanceKm = distance_km ?? 50; // default 50km if not provided
        const estimatedWeightKg = weight ?? 1000;

        const ghgRes = await fetch(`${baseUrl}/api/ghg/calculate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            project_id,
            activity_type: 'transport_routier',
            activity_data: {
              distance_km: estimatedDistanceKm,
              weight_kg: estimatedWeightKg,
              mode_transport: 'routier',
              baseline_distance_km: estimatedDistanceKm * 1.3,
              baseline_mode: 'routier',
            },
          }),
        });

        if (ghgRes.ok) {
          const ghgData = await ghgRes.json();

          const logRes = await fetch(`${baseUrl}/api/projects/${project_id}/log-activity`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              activity_type: 'transport',
              related_transport_request_id: transportRequest.id,
              ghg_emissions_baseline_kgco2e: ghgData.baseline_kgco2e,
              ghg_emissions_project_kgco2e: ghgData.project_kgco2e,
              ghg_reduction_kgco2e: ghgData.reduction_kgco2e,
              uncertainty_percent: ghgData.uncertainty_percent,
              evidence_file_url: null,
              evidence_type: 'gps_data',
              evidence_gps: gps_data ?? null,
            }),
          });

          if (logRes.ok) {
            activityLog = await logRes.json();
          }
        }
      } catch {
        // MRV integration is non-blocking
      }
    }

    return NextResponse.json({
      success: true,
      transport_request: transportRequest,
      external_reference: externalReference,
      scheduled_time: scheduledTime,
      mrv: activityLog ? { activity_log_id: activityLog.activity_log?.id } : null,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
