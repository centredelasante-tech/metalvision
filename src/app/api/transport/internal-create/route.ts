import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * POST /api/transport/internal-create
 *
 * Creates an internal transport request (METALTRACE internal fleet or client transport).
 * Stores proof files, creates MRV activity log, and returns status "scheduled".
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const {
      lot_id,
      container_id,
      pickup_address,
      dropoff_address,
      driver_name,
      truck_number,
      arrival_eta,
      transport_mode = 'camion',
      gps_start,
      proof_photo_url,
      proof_document_url,
      // Client transport fields
      provider = 'internal',
      client_transporter_name,
      // MRV fields
      project_id,
      distance_km,
      weight_kg,
      notes,
    } = body;

    if (!lot_id || typeof lot_id !== 'string') {
      return NextResponse.json({ error: 'lot_id is required' }, { status: 400 });
    }

    const supabase = await createClient();

    // Check external_transport_enabled setting
    const { data: setting } = await supabase
      .from('app_settings')
      .select('value')
      .eq('key', 'external_transport_enabled')
      .maybeSingle();

    const externalEnabled = setting?.value === true || setting?.value === 'true';

    // Always use internal flow unless external is explicitly enabled
    const resolvedProvider = externalEnabled ? provider : 'internal';

    // ── Insert transport request ─────────────────────────────────────────────
    const { data: transportRequest, error } = await supabase
      .from('transport_requests')
      .insert({
        lot_id,
        container_id: container_id ?? null,
        pickup_address: pickup_address ?? 'METALTRACE — Adresse de collecte',
        dropoff_address: dropoff_address ?? 'METALTRACE — Centre de traitement',
        provider: resolvedProvider,
        driver_name: driver_name ?? null,
        truck_number: truck_number ?? null,
        arrival_eta: arrival_eta ?? null,
        transport_mode: transport_mode,
        gps_start: gps_start ?? null,
        proof_photo_url: proof_photo_url ?? null,
        proof_document_url: proof_document_url ?? null,
        client_transporter_name: client_transporter_name ?? null,
        transport_status: 'scheduled',
        transporter: resolvedProvider === 'internal' ? 'Transport interne METALTRACE' : (client_transporter_name ?? 'Transport du client'),
        notes: notes ?? null,
      })
      .select()
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    // ── Store proof files in evidence_files ──────────────────────────────────
    const evidenceInserts = [];
    if (proof_photo_url && project_id) {
      evidenceInserts.push({
        project_id,
        file_url: proof_photo_url,
        type: 'proof_photo',
        related_activity_log_id: null,
        gps: gps_start ?? null,
        timestamp: new Date().toISOString(),
      });
    }
    if (proof_document_url && project_id) {
      evidenceInserts.push({
        project_id,
        file_url: proof_document_url,
        type: 'proof_document',
        related_activity_log_id: null,
        gps: null,
        timestamp: new Date().toISOString(),
      });
    }
    if (evidenceInserts.length > 0) {
      await supabase.from('evidence_files').insert(evidenceInserts);
    }

    // ── MRV: GHG calculation + activity log ──────────────────────────────────
    let activityLog = null;
    if (project_id) {
      try {
        const baseUrl = process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000';
        const estimatedDistanceKm = distance_km ?? 50;
        const estimatedWeightKg = weight_kg ?? 1000;

        const ghgRes = await fetch(`${baseUrl}/api/ghg/calculate`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            project_id,
            activity_type: 'transport_interne',
            activity_data: {
              distance_km: estimatedDistanceKm,
              weight_kg: estimatedWeightKg,
              mode_transport: transport_mode,
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
              activity_type: 'transport_interne',
              related_transport_request_id: transportRequest.id,
              ghg_emissions_baseline_kgco2e: ghgData.baseline_kgco2e,
              ghg_emissions_project_kgco2e: ghgData.project_kgco2e,
              ghg_reduction_kgco2e: ghgData.reduction_kgco2e,
              uncertainty_percent: ghgData.uncertainty_percent,
              evidence_file_url: proof_photo_url ?? null,
              evidence_type: 'transport_proof',
              evidence_gps: gps_start ?? null,
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
      status: 'scheduled',
      provider: resolvedProvider,
      mrv: activityLog ? { activity_log_id: activityLog.activity_log?.id } : null,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
