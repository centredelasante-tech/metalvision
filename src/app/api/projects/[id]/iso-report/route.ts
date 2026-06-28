import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * GET /api/projects/[id]/iso-report
 *
 * Generates an ISO 14064-2 compliant report in JSON format.
 * Includes: project description, baseline, project scenario, methodology,
 * emission factors, MRV activities, GHG reductions, uncertainties,
 * evidence files, and verification status.
 */
export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id: project_id } = await params;
    const supabase = await createClient();

    // ── Fetch all project data ───────────────────────────────────────────────
    const [projectRes, logsRes, evidenceRes, sessionsRes, factorsRes] = await Promise.all([
      supabase.from('projects').select('*').eq('id', project_id).maybeSingle(),
      supabase.from('project_activity_logs').select('*').eq('project_id', project_id).order('timestamp', { ascending: true }),
      supabase.from('evidence_files').select('*').eq('project_id', project_id).order('timestamp', { ascending: true }),
      supabase.from('verification_sessions').select('*').eq('project_id', project_id).order('created_at', { ascending: false }),
      supabase.from('emission_factors').select('*').order('category'),
    ]);

    if (projectRes.error) return NextResponse.json({ error: projectRes.error.message }, { status: 500 });
    if (!projectRes.data) return NextResponse.json({ error: 'Project not found' }, { status: 404 });

    const project = projectRes.data;
    const logs = logsRes.data ?? [];
    const evidence = evidenceRes.data ?? [];
    const sessions = sessionsRes.data ?? [];
    const factors = factorsRes.data ?? [];

    // ── Aggregate GHG totals ─────────────────────────────────────────────────
    const totalBaseline = logs.reduce((sum, l) => sum + (l.ghg_emissions_baseline_kgco2e ?? 0), 0);
    const totalProject = logs.reduce((sum, l) => sum + (l.ghg_emissions_project_kgco2e ?? 0), 0);
    const totalReduction = logs.reduce((sum, l) => sum + (l.ghg_reduction_kgco2e ?? 0), 0);
    const avgUncertainty = logs.length > 0
      ? logs.reduce((sum, l) => sum + (l.uncertainty_percent ?? 0), 0) / logs.length
      : 0;

    // ── Build ISO report structure ───────────────────────────────────────────
    const report = {
      report_metadata: {
        standard: 'ISO 14064-2:2019',
        generated_at: new Date().toISOString(),
        report_version: '1.0',
        generator: 'MetalVision MRV Platform',
      },
      project: {
        id: project.id,
        name: project.name,
        description: project.description,
        status: project.status,
        start_date: project.start_date,
        end_date: project.end_date,
        system_boundaries: project.system_boundaries,
      },
      baseline: {
        description: project.baseline_description,
        total_emissions_kgco2e: Math.round(totalBaseline * 100) / 100,
        total_emissions_tco2e: Math.round((totalBaseline / 1000) * 100) / 100,
      },
      project_scenario: {
        description: project.project_scenario_description,
        total_emissions_kgco2e: Math.round(totalProject * 100) / 100,
        total_emissions_tco2e: Math.round((totalProject / 1000) * 100) / 100,
      },
      ghg_reductions: {
        total_reduction_kgco2e: Math.round(totalReduction * 100) / 100,
        total_reduction_tco2e: Math.round((totalReduction / 1000) * 100) / 100,
        average_uncertainty_percent: Math.round(avgUncertainty * 100) / 100,
        reduction_percentage: totalBaseline > 0
          ? Math.round((totalReduction / totalBaseline) * 10000) / 100
          : 0,
      },
      methodology: {
        approach: 'Activity-based GHG accounting',
        calculation_method: 'E = Σ(activity × emission_factor)',
        uncertainty_method: 'Simple quadratic propagation',
        reference_standards: ['ISO 14064-2:2019', 'ADEME Base Carbone 2023', 'GHG Protocol'],
      },
      emission_factors: factors.map((ef) => ({
        category: ef.category,
        source: ef.source_reference,
        unit: ef.unit,
        value: ef.value,
        uncertainty_percent: ef.uncertainty_percent,
        valid_from: ef.valid_from,
        valid_to: ef.valid_to,
        version: ef.version,
      })),
      mrv_activities: logs.map((log) => ({
        id: log.id,
        activity_type: log.activity_type,
        timestamp: log.timestamp,
        baseline_kgco2e: log.ghg_emissions_baseline_kgco2e,
        project_kgco2e: log.ghg_emissions_project_kgco2e,
        reduction_kgco2e: log.ghg_reduction_kgco2e,
        uncertainty_percent: log.uncertainty_percent,
        related_lot_id: log.related_lot_id,
        related_transport_id: log.related_transport_request_id,
      })),
      evidence: evidence.map((ev) => ({
        id: ev.id,
        type: ev.type,
        file_url: ev.file_url,
        timestamp: ev.timestamp,
        gps: ev.gps,
        related_activity_log_id: ev.related_activity_log_id,
      })),
      verification: {
        sessions: sessions.map((s) => ({
          id: s.id,
          verifier_org: s.verifier_org,
          verifier_contact: s.verifier_contact,
          status: s.status,
          scope: s.scope,
          report_url: s.report_url,
          comments: s.comments,
          created_at: s.created_at,
        })),
        latest_status: sessions[0]?.status ?? 'not_started',
      },
    };

    return NextResponse.json(report, {
      headers: {
        'Content-Disposition': `attachment; filename="iso-report-${project_id}-${new Date().toISOString().split('T')[0]}.json"`,
        'Content-Type': 'application/json',
      },
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
