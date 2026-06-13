import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * POST /api/stats/update
 *
 * UpdateGlobalStats — reads ALL raw_measurements (anonymously, no client_id exposed),
 * computes per-metal and per-object aggregates, and writes to global_stats / object_profiles.
 *
 * This endpoint uses the service-role client to bypass RLS and read across all clients.
 * No client_id is ever exposed in the output tables.
 */
export async function POST(_req: NextRequest) {
  try {
    // Use service-role client to read all rows across clients (bypasses RLS)
    const { createClient: createServiceClient } = await import('@supabase/supabase-js');
    const serviceClient = createServiceClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!
    );

    // ── Read all confirmed measurements (those with official_weight_kg set) ──
    const { data: rows, error: fetchError } = await serviceClient
      .from('raw_measurements')
      .select(
        'metal_type_predicted, official_metal_type, volume_estimated_m3, official_weight_kg, density_real, compaction_visual, purity_visual, object_type, width_cm, height_cm, depth_cm'
      );

    if (fetchError) {
      return NextResponse.json({ error: fetchError.message }, { status: 500 });
    }

    if (!rows || rows.length === 0) {
      return NextResponse.json({ success: true, message: 'No measurements to process', metals_updated: 0, objects_updated: 0 });
    }

    // ── Aggregate by metal_type ──────────────────────────────────────────────
    type MetalAgg = {
      densities: number[];
      compactions: number[];
      purities: number[];
      volumeErrors: number[];
      count: number;
    };

    const metalMap: Record<string, MetalAgg> = {};

    for (const row of rows) {
      // Use official_metal_type if confirmed, otherwise predicted
      const metalType: string = (row.official_metal_type ?? row.metal_type_predicted ?? '').toLowerCase().trim();
      if (!metalType) continue;

      if (!metalMap[metalType]) {
        metalMap[metalType] = { densities: [], compactions: [], purities: [], volumeErrors: [], count: 0 };
      }

      metalMap[metalType].count += 1;

      if (typeof row.density_real === 'number' && row.density_real > 0) {
        metalMap[metalType].densities.push(row.density_real);
      }
      if (typeof row.compaction_visual === 'number') {
        metalMap[metalType].compactions.push(row.compaction_visual);
      }
      if (typeof row.purity_visual === 'number') {
        metalMap[metalType].purities.push(row.purity_visual);
      }
      // Volume error: difference between estimated volume and volume derived from official weight
      if (
        typeof row.volume_estimated_m3 === 'number' &&
        typeof row.official_weight_kg === 'number' &&
        typeof row.density_real === 'number' &&
        row.density_real > 0
      ) {
        const officialVolume = row.official_weight_kg / row.density_real;
        const volumeError = Math.abs(row.volume_estimated_m3 - officialVolume);
        metalMap[metalType].volumeErrors.push(volumeError);
      }
    }

    const avg = (arr: number[]): number | null =>
      arr.length > 0 ? arr.reduce((a, b) => a + b, 0) / arr.length : null;

    // Upsert global_stats (no client_id)
    let metalsUpdated = 0;
    for (const [metalType, agg] of Object.entries(metalMap)) {
      const { error: upsertError } = await serviceClient
        .from('global_stats')
        .upsert(
          {
            metal_type: metalType,
            density_mean: avg(agg.densities),
            compaction_mean: avg(agg.compactions),
            purity_mean: avg(agg.purities),
            volume_error_mean: avg(agg.volumeErrors),
            nb_measurements: agg.count,
            updated_at: new Date().toISOString(),
          },
          { onConflict: 'metal_type' }
        );

      if (!upsertError) metalsUpdated++;
    }

    // ── Aggregate by object_type ─────────────────────────────────────────────
    type ObjectAgg = {
      widths: number[];
      heights: number[];
      depths: number[];
      weights: number[];
      densities: number[];
      count: number;
    };

    const objectMap: Record<string, ObjectAgg> = {};

    for (const row of rows) {
      const objectType: string = (row.object_type ?? '').toLowerCase().trim();
      if (!objectType) continue;

      if (!objectMap[objectType]) {
        objectMap[objectType] = { widths: [], heights: [], depths: [], weights: [], densities: [], count: 0 };
      }

      objectMap[objectType].count += 1;

      if (typeof row.width_cm === 'number' && row.width_cm > 0) objectMap[objectType].widths.push(row.width_cm);
      if (typeof row.height_cm === 'number' && row.height_cm > 0) objectMap[objectType].heights.push(row.height_cm);
      if (typeof row.depth_cm === 'number' && row.depth_cm > 0) objectMap[objectType].depths.push(row.depth_cm);
      if (typeof row.official_weight_kg === 'number' && row.official_weight_kg > 0) {
        objectMap[objectType].weights.push(row.official_weight_kg);
      }
      if (typeof row.density_real === 'number' && row.density_real > 0) {
        objectMap[objectType].densities.push(row.density_real);
      }
    }

    // Upsert object_profiles (no client_id)
    let objectsUpdated = 0;
    for (const [objectType, agg] of Object.entries(objectMap)) {
      const { error: upsertError } = await serviceClient
        .from('object_profiles')
        .upsert(
          {
            object_type: objectType,
            avg_width_cm: avg(agg.widths),
            avg_height_cm: avg(agg.heights),
            avg_depth_cm: avg(agg.depths),
            avg_weight_kg: avg(agg.weights),
            density_mean: avg(agg.densities),
            nb_measurements: agg.count,
            updated_at: new Date().toISOString(),
          },
          { onConflict: 'object_type' }
        );

      if (!upsertError) objectsUpdated++;
    }

    return NextResponse.json({
      success: true,
      metals_updated: metalsUpdated,
      objects_updated: objectsUpdated,
      total_measurements_processed: rows.length,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
