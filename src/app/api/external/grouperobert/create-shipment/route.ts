import { NextRequest, NextResponse } from 'next/server';

/**
 * POST /external/grouperobert/create-shipment
 *
 * PLACEHOLDER — Simulates the Groupe Robert external API endpoint.
 * Replace the URL in /api/transport/create with the real Groupe Robert API URL
 * when credentials are available.
 *
 * Body (JSON):
 *   pickup_address  : string
 *   dropoff_address : string
 *   weight          : number
 *   description     : string
 *   reference       : string  (lot_id)
 *
 * Returns:
 *   external_reference : string
 *   scheduled_time     : string (ISO)
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { pickup_address, dropoff_address, weight, description, reference } = body;

    if (!pickup_address || !dropoff_address || !reference) {
      return NextResponse.json(
        { error: 'pickup_address, dropoff_address, and reference are required' },
        { status: 400 }
      );
    }

    // ── Mock response simulating Groupe Robert API ───────────────────────────
    const externalReference = `GR-${new Date().getFullYear()}-${String(Math.floor(Math.random() * 90000) + 10000)}`;
    const scheduledTime = new Date(Date.now() + 4 * 60 * 60 * 1000).toISOString(); // +4h

    return NextResponse.json({
      success: true,
      external_reference: externalReference,
      scheduled_time: scheduledTime,
      carrier: 'Groupe Robert',
      reference,
      pickup_address,
      dropoff_address,
      weight: weight ?? 0,
      description: description ?? '',
      // NOTE: Replace this mock with real Groupe Robert API integration
      // Real endpoint: https://api.grouperobert.com/create-shipment
      // Auth: Bearer token from GROUPE_ROBERT_API_KEY env variable
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
