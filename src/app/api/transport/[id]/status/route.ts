import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

const VALID_STATUSES = ['scheduled', 'in_transit', 'arrived', 'delivered'];

/**
 * GET /api/transport/{id}/status
 * Returns current status of a transport request.
 *
 * PATCH /api/transport/{id}/status
 * Manually updates the status of a transport request.
 */

export async function GET(
  _req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const supabase = await createClient();

    const { data, error } = await supabase
      .from('transport_requests')
      .select('id, lot_id, transport_status, provider, driver_name, truck_number, arrival_eta, gps_start, gps_end, proof_photo_url, proof_document_url, updated_at')
      .eq('id', id)
      .maybeSingle();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }
    if (!data) {
      return NextResponse.json({ error: 'Transport request not found' }, { status: 404 });
    }

    return NextResponse.json({
      id: data.id,
      lot_id: data.lot_id,
      status: data.transport_status,
      provider: data.provider,
      driver_name: data.driver_name,
      truck_number: data.truck_number,
      arrival_eta: data.arrival_eta,
      gps_start: data.gps_start,
      gps_end: data.gps_end,
      proof_photo_url: data.proof_photo_url,
      proof_document_url: data.proof_document_url,
      updated_at: data.updated_at,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function PATCH(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const body = await req.json();
    const { new_status, gps_end, notes } = body;

    if (!new_status || !VALID_STATUSES.includes(new_status)) {
      return NextResponse.json(
        { error: `new_status must be one of: ${VALID_STATUSES.join(', ')}` },
        { status: 400 }
      );
    }

    const supabase = await createClient();

    const updateData: Record<string, unknown> = { transport_status: new_status };
    if (gps_end) updateData.gps_end = gps_end;
    if (notes) updateData.notes = notes;

    const { data: updated, error } = await supabase
      .from('transport_requests')
      .update(updateData)
      .eq('id', id)
      .select()
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({
      success: true,
      transport_request: updated,
      status: new_status,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
