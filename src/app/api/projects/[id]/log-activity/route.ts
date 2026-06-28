import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * POST /api/projects/[id]/log-activity
 *
 * Creates a project_activity_log entry with GHG data.
 *
 * Body:
 *   activity_type                  : string
 *   related_lot_id?                : string
 *   related_container_id?          : string
 *   related_transport_request_id?  : string
 *   raw_data_ref?                  : string
 *   ghg_emissions_baseline_kgco2e  : number
 *   ghg_emissions_project_kgco2e   : number
 *   ghg_reduction_kgco2e           : number
 *   uncertainty_percent            : number
 *   actor_id?                      : string
 *   evidence_file_url?             : string
 *   evidence_type?                 : string
 *   evidence_gps?                  : object
 */
export async function POST(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id: project_id } = await params;
    const body = await req.json();

    const {
      activity_type,
      related_lot_id,
      related_container_id,
      related_transport_request_id,
      raw_data_ref,
      ghg_emissions_baseline_kgco2e,
      ghg_emissions_project_kgco2e,
      ghg_reduction_kgco2e,
      uncertainty_percent,
      actor_id,
      evidence_file_url,
      evidence_type,
      evidence_gps,
    } = body;

    if (!project_id) {
      return NextResponse.json({ error: 'project_id is required' }, { status: 400 });
    }
    if (!activity_type) {
      return NextResponse.json({ error: 'activity_type is required' }, { status: 400 });
    }

    const supabase = await createClient();

    // ── Create activity log ──────────────────────────────────────────────────
    const { data: log, error: logError } = await supabase
      .from('project_activity_logs')
      .insert({
        project_id,
        activity_type,
        related_lot_id: related_lot_id ?? null,
        related_container_id: related_container_id ?? null,
        related_transport_request_id: related_transport_request_id ?? null,
        raw_data_ref: raw_data_ref ?? null,
        ghg_emissions_baseline_kgco2e: ghg_emissions_baseline_kgco2e ?? 0,
        ghg_emissions_project_kgco2e: ghg_emissions_project_kgco2e ?? 0,
        ghg_reduction_kgco2e: ghg_reduction_kgco2e ?? 0,
        uncertainty_percent: uncertainty_percent ?? 5,
        actor_id: actor_id ?? null,
        timestamp: new Date().toISOString(),
      })
      .select()
      .single();

    if (logError) {
      return NextResponse.json({ error: logError.message }, { status: 500 });
    }

    // ── Attach evidence file if provided ─────────────────────────────────────
    let evidence = null;
    if (evidence_file_url) {
      const { data: ev, error: evError } = await supabase
        .from('evidence_files')
        .insert({
          project_id,
          file_url: evidence_file_url,
          type: evidence_type ?? 'document',
          related_activity_log_id: log.id,
          gps: evidence_gps ?? null,
          actor_id: actor_id ?? null,
          timestamp: new Date().toISOString(),
        })
        .select()
        .single();

      if (!evError) evidence = ev;
    }

    return NextResponse.json({
      success: true,
      activity_log: log,
      evidence_file: evidence,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

/**
 * GET /api/projects/[id]/log-activity
 * Returns all activity logs for a project
 */
export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id: project_id } = await params;
    const supabase = await createClient();

    const { data, error } = await supabase
      .from('project_activity_logs')
      .select('*')
      .eq('project_id', project_id)
      .order('timestamp', { ascending: false });

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ logs: data });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
