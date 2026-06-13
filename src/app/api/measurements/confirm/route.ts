import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * POST /api/measurements/confirm
 *
 * ConfirmOfficialMeasurement — integrates official weighing data into a raw measurement.
 *
 * Body (JSON):
 *   measurement_id  : string  — UUID of the raw_measurements row
 *   client_id       : string  — UUID of the client (must match the row's client_id)
 *   official_weight_kg  : number
 *   official_metal_type : string
 *   price_paid          : number
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { measurement_id, client_id, official_weight_kg, official_metal_type, price_paid } = body;

    // ── Validate inputs ──────────────────────────────────────────────────────
    if (!measurement_id || typeof measurement_id !== 'string') {
      return NextResponse.json({ error: 'measurement_id is required' }, { status: 400 });
    }
    if (!client_id || typeof client_id !== 'string') {
      return NextResponse.json({ error: 'client_id is required' }, { status: 400 });
    }
    if (typeof official_weight_kg !== 'number' || official_weight_kg <= 0) {
      return NextResponse.json({ error: 'official_weight_kg must be a positive number' }, { status: 400 });
    }
    if (!official_metal_type || typeof official_metal_type !== 'string') {
      return NextResponse.json({ error: 'official_metal_type is required' }, { status: 400 });
    }
    if (typeof price_paid !== 'number' || price_paid < 0) {
      return NextResponse.json({ error: 'price_paid must be a non-negative number' }, { status: 400 });
    }

    const supabase = await createClient();

    // ── Read the row — strict client_id filter ───────────────────────────────
    const { data: row, error: fetchError } = await supabase
      .from('raw_measurements')
      .select('id, client_id, volume_estimated_m3')
      .eq('id', measurement_id)
      .eq('client_id', client_id)
      .maybeSingle();

    if (fetchError) {
      return NextResponse.json({ error: fetchError.message }, { status: 500 });
    }

    // Row not found OR client_id mismatch — refuse update
    if (!row) {
      return NextResponse.json(
        { error: 'Measurement not found or client_id does not match. Update refused.' },
        { status: 403 }
      );
    }

    // ── Calculate density_real ───────────────────────────────────────────────
    const volumeM3: number = row.volume_estimated_m3 ?? 0;
    let densityReal: number | null = null;
    if (volumeM3 > 0) {
      densityReal = Math.round((official_weight_kg / volumeM3) * 10000) / 10000;
    }

    // ── Update the row ───────────────────────────────────────────────────────
    const { data: updated, error: updateError } = await supabase
      .from('raw_measurements')
      .update({
        official_weight_kg,
        official_metal_type,
        density_real: densityReal,
        price_paid,
      })
      .eq('id', measurement_id)
      .eq('client_id', client_id)
      .select()
      .single();

    if (updateError) {
      return NextResponse.json({ error: updateError.message }, { status: 500 });
    }

    return NextResponse.json({
      success: true,
      measurement_id: updated.id,
      density_real: densityReal,
      official_weight_kg: updated.official_weight_kg,
      official_metal_type: updated.official_metal_type,
      price_paid: updated.price_paid,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
