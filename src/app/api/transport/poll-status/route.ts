import { NextResponse } from 'next/server';

/**
 * POST /api/transport/poll-status
 *
 * DEPRECATED: External Groupe Robert polling has been removed.
 * Internal transport uses manual status updates via /api/transport/{id}/status (PATCH)
 * or /api/transport/update-status (POST).
 */
export async function POST() {
  return NextResponse?.json({
    success: false,
    message: 'External transport polling is disabled. METALTRACE uses internal transport only. Use PATCH /api/transport/{id}/status for manual updates.',
    external_transport_enabled: false,
  }, { status: 410 });
}
