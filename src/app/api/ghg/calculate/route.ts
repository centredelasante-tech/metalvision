import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * POST /api/ghg/calculate
 *
 * Calculates GHG emissions: baseline vs project scenario.
 * Returns baseline_kgco2e, project_kgco2e, reduction_kgco2e, uncertainty_percent
 *
 * Body:
 *   project_id     : string
 *   activity_type  : string  (e.g. "transport_routier", "recyclage_acier")
 *   activity_data  : {
 *     distance_km?   : number
 *     weight_kg?     : number
 *     mode_transport?: string  ("routier" | "ferroviaire" | "maritime")
 *     energy_kwh?    : number
 *     baseline_distance_km? : number
 *     baseline_mode?        : string
 *   }
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { project_id, activity_type, activity_data } = body;

    if (!project_id || typeof project_id !== 'string') {
      return NextResponse.json({ error: 'project_id is required' }, { status: 400 });
    }
    if (!activity_type || typeof activity_type !== 'string') {
      return NextResponse.json({ error: 'activity_type is required' }, { status: 400 });
    }
    if (!activity_data || typeof activity_data !== 'object') {
      return NextResponse.json({ error: 'activity_data is required' }, { status: 400 });
    }

    const supabase = await createClient();

    // ── Verify project exists ────────────────────────────────────────────────
    const { data: project, error: projError } = await supabase
      .from('projects')
      .select('id, status')
      .eq('id', project_id)
      .maybeSingle();

    if (projError) {
      return NextResponse.json({ error: projError.message }, { status: 500 });
    }
    if (!project) {
      return NextResponse.json({ error: 'Project not found' }, { status: 404 });
    }

    // ── Fetch relevant emission factors ──────────────────────────────────────
    const { data: factors, error: efError } = await supabase
      .from('emission_factors')
      .select('*')
      .or(`category.eq.${activity_type},category.ilike.%transport%`)
      .order('valid_from', { ascending: false });

    if (efError) {
      return NextResponse.json({ error: efError.message }, { status: 500 });
    }

    // ── GHG Calculation Logic ────────────────────────────────────────────────
    const {
      distance_km = 0,
      weight_kg = 0,
      mode_transport = 'routier',
      energy_kwh = 0,
      baseline_distance_km,
      baseline_mode = 'routier',
    } = activity_data;

    const tkm = (weight_kg / 1000) * distance_km; // tonne-km
    const baseline_tkm = (weight_kg / 1000) * (baseline_distance_km ?? distance_km * 1.3);

    // Find emission factor for project mode
    const projectCategory = `transport_${mode_transport}`;
    const baselineCategory = `transport_${baseline_mode}`;

    const findFactor = (category: string): { value: number; uncertainty: number } => {
      const ef = factors?.find((f) => f.category === category);
      if (ef) return { value: ef.value, uncertainty: ef.uncertainty_percent ?? 5 };
      // Fallback defaults (ADEME 2023)
      const defaults: Record<string, { value: number; uncertainty: number }> = {
        transport_routier:      { value: 0.062, uncertainty: 5 },
        transport_ferroviaire:  { value: 0.0028, uncertainty: 3 },
        transport_maritime:     { value: 0.011, uncertainty: 7 },
        recyclage_acier:        { value: -1.85, uncertainty: 8 },
        recyclage_aluminium:    { value: -8.14, uncertainty: 8 },
        recyclage_cuivre:       { value: -3.5, uncertainty: 8 },
        energie_electricite:    { value: 0.0175, uncertainty: 4 }, // Québec hydro
      };
      return defaults[category] ?? { value: 0.062, uncertainty: 5 };
    };

    const projectFactor = findFactor(projectCategory);
    const baselineFactor = findFactor(baselineCategory);

    // E = activity × FE
    let baseline_kgco2e = baseline_tkm * baselineFactor.value;
    let project_kgco2e = tkm * projectFactor.value;

    // Add energy component if provided
    if (energy_kwh > 0) {
      const energyFactor = findFactor('energie_electricite');
      project_kgco2e += energy_kwh * energyFactor.value;
    }

    // For recycling activities
    if (activity_type.startsWith('recyclage')) {
      const recyclingFactor = findFactor(activity_type);
      baseline_kgco2e = weight_kg * Math.abs(recyclingFactor.value) * 1.2; // baseline = primary production
      project_kgco2e = weight_kg * Math.abs(recyclingFactor.value) * 0.1;  // project = secondary recycling
    }

    const reduction_kgco2e = baseline_kgco2e - project_kgco2e;

    // Uncertainty propagation (simple quadratic sum)
    const u_baseline = baselineFactor.uncertainty / 100;
    const u_project = projectFactor.uncertainty / 100;
    const uncertainty_percent = Math.round(
      Math.sqrt(u_baseline * u_baseline + u_project * u_project) * 100 * 100
    ) / 100;

    const result = {
      baseline_kgco2e: Math.round(baseline_kgco2e * 100) / 100,
      project_kgco2e: Math.round(project_kgco2e * 100) / 100,
      reduction_kgco2e: Math.round(reduction_kgco2e * 100) / 100,
      uncertainty_percent,
      factors_used: {
        baseline: { category: baselineCategory, value: baselineFactor.value },
        project: { category: projectCategory, value: projectFactor.value },
      },
    };

    return NextResponse.json(result);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
