import { NextRequest, NextResponse } from 'next/server';

/**
 * GET /external/grouperobert/shipment-status?ref=xxxx
 *
 * PLACEHOLDER — Simulates the Groupe Robert shipment status endpoint.
 * Replace with real Groupe Robert API URL when credentials are available.
 *
 * Query params:
 *   ref : string  (external_reference)
 *
 * Returns:
 *   status : 'assigned' | 'en_route' | 'picked_up' | 'delivered'
 */
export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const ref = searchParams.get('ref');

    if (!ref) {
      return NextResponse.json({ error: 'Query parameter "ref" is required' }, { status: 400 });
    }

    // ── Mock status cycling based on reference suffix ────────────────────────
    const MOCK_STATUSES = ['assigned', 'en_route', 'picked_up', 'delivered'] as const;
    const refNum = parseInt(ref.replace(/\D/g, '').slice(-1) || '0', 10);
    const mockStatus = MOCK_STATUSES[refNum % MOCK_STATUSES.length];

    return NextResponse.json({
      success: true,
      external_reference: ref,
      status: mockStatus,
      carrier: 'Groupe Robert',
      last_updated: new Date().toISOString(),
      // NOTE: Replace this mock with real Groupe Robert API integration
      // Real endpoint: https://api.grouperobert.com/shipment-status?ref={ref}
      // Auth: Bearer token from GROUPE_ROBERT_API_KEY env variable
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
