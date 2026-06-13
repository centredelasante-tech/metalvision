import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * POST /api/predict
 *
 * PredictForNewPhoto — estimates weight and value using anonymized global statistics.
 *
 * Body (JSON):
 *   client_id           : string   — required, identifies the requesting client
 *   metal_type_predicted: string   — from AnalysePhotoMetalvision
 *   volume_estimated_m3 : number   — from AnalysePhotoMetalvision
 *   object_type         : string | null — from AnalysePhotoMetalvision
 *   metal_price_per_kg  : number   — optional, to compute valeur_estimée
 *
 * Logic:
 *   If object_type is known in object_profiles → use avg_weight_kg
 *   Else → use global_stats[metal_type].density_mean * volume_estimated_m3
 *
 * Returns:
 *   poids_estime        : number (kg)
 *   intervalle_confiance: { min: number, max: number }
 *   valeur_estimee      : number | null
 *   method              : 'object_profile' | 'global_stats' | 'fallback'
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const {
      client_id,
      metal_type_predicted,
      volume_estimated_m3,
      object_type,
      metal_price_per_kg,
    } = body;

    // ── Validate inputs ──────────────────────────────────────────────────────
    if (!client_id || typeof client_id !== 'string') {
      return NextResponse.json({ error: 'client_id is required' }, { status: 400 });
    }
    if (!metal_type_predicted || typeof metal_type_predicted !== 'string') {
      return NextResponse.json({ error: 'metal_type_predicted is required' }, { status: 400 });
    }
    if (typeof volume_estimated_m3 !== 'number' || volume_estimated_m3 <= 0) {
      return NextResponse.json({ error: 'volume_estimated_m3 must be a positive number' }, { status: 400 });
    }

    const supabase = await createClient();

    let poidsEstime: number;
    let method: 'object_profile' | 'global_stats' | 'fallback';
    let volumeErrorMean: number | null = null;

    // ── Strategy 1: object_type known → use object_profiles ─────────────────
    if (object_type && typeof object_type === 'string' && object_type.trim() !== '') {
      const { data: profile } = await supabase
        .from('object_profiles')
        .select('avg_weight_kg, density_mean, nb_measurements')
        .eq('object_type', object_type.toLowerCase().trim())
        .maybeSingle();

      if (profile && typeof profile.avg_weight_kg === 'number' && profile.avg_weight_kg > 0) {
        poidsEstime = profile.avg_weight_kg;
        method = 'object_profile';
        // Confidence interval: ±15% for object profiles (typical variance)
        volumeErrorMean = poidsEstime * 0.15;
      } else {
        // Object type not in profiles yet — fall through to global_stats
        method = 'global_stats';
        poidsEstime = await estimateFromGlobalStats(supabase, metal_type_predicted, volume_estimated_m3);
        volumeErrorMean = await getVolumeErrorMean(supabase, metal_type_predicted);
      }
    } else {
      // ── Strategy 2: no object_type → use global_stats density_mean ─────────
      method = 'global_stats';
      poidsEstime = await estimateFromGlobalStats(supabase, metal_type_predicted, volume_estimated_m3);
      volumeErrorMean = await getVolumeErrorMean(supabase, metal_type_predicted);
    }

    // ── Confidence interval ──────────────────────────────────────────────────
    // Based on volume_error_mean: propagate volume uncertainty to weight uncertainty
    // If no volume_error_mean available, use ±20% fallback
    let confidenceRange: number;
    if (volumeErrorMean !== null && volumeErrorMean > 0) {
      // Approximate weight uncertainty from volume error
      const { data: stats } = await supabase
        .from('global_stats')
        .select('density_mean')
        .eq('metal_type', metal_type_predicted.toLowerCase().trim())
        .maybeSingle();
      const densityForInterval = stats?.density_mean ?? 5000;
      confidenceRange = volumeErrorMean * densityForInterval;
    } else {
      confidenceRange = poidsEstime * 0.2;
    }

    const intervalleConfiance = {
      min: Math.max(0, Math.round((poidsEstime - confidenceRange) * 100) / 100),
      max: Math.round((poidsEstime + confidenceRange) * 100) / 100,
    };

    // ── Estimated value ──────────────────────────────────────────────────────
    let valeurEstimee: number | null = null;
    if (typeof metal_price_per_kg === 'number' && metal_price_per_kg > 0) {
      valeurEstimee = Math.round(poidsEstime * metal_price_per_kg * 100) / 100;
    }

    return NextResponse.json({
      poids_estime: Math.round(poidsEstime * 100) / 100,
      intervalle_confiance: intervalleConfiance,
      valeur_estimee: valeurEstimee,
      method,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

const FALLBACK_DENSITIES: Record<string, number> = {
  aluminium: 2700,
  cuivre: 8960,
  laiton: 8500,
  acier: 7850,
  inox: 8000,
  fonte: 7200,
  mélange: 5000,
};

async function estimateFromGlobalStats(
  supabase: Awaited<ReturnType<typeof createClient>>,
  metalType: string,
  volumeM3: number
): Promise<number> {
  const { data: stats } = await supabase
    .from('global_stats')
    .select('density_mean')
    .eq('metal_type', metalType.toLowerCase().trim())
    .maybeSingle();

  const density = stats?.density_mean ?? FALLBACK_DENSITIES[metalType.toLowerCase()] ?? 5000;
  return volumeM3 * density;
}

async function getVolumeErrorMean(
  supabase: Awaited<ReturnType<typeof createClient>>,
  metalType: string
): Promise<number | null> {
  const { data: stats } = await supabase
    .from('global_stats')
    .select('volume_error_mean')
    .eq('metal_type', metalType.toLowerCase().trim())
    .maybeSingle();

  return stats?.volume_error_mean ?? null;
}
