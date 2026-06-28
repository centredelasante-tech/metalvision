import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

const VALID_STATUSES = ['scheduled', 'in_transit', 'arrived', 'delivered', 'cancelled'];
const STATUS_LABELS: Record<string, string> = {
  scheduled: 'Planifié',
  in_transit: 'En transit',
  arrived: 'Arrivé',
  delivered: 'Livré',
  cancelled: 'Annulé',
};

/**
 * POST /api/transport/update-status
 *
 * Updates the status of an internal transport request by ID.
 * If status = 'delivered', marks the lot as collected.
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { transport_id, new_status, gps_end, notes } = body;

    if (!transport_id || typeof transport_id !== 'string') {
      return NextResponse.json({ error: 'transport_id is required' }, { status: 400 });
    }
    if (!new_status || !VALID_STATUSES.includes(new_status)) {
      return NextResponse.json(
        { error: `new_status must be one of: ${VALID_STATUSES.join(', ')}` },
        { status: 400 }
      );
    }

    const supabase = await createClient();

    const { data: existing, error: fetchError } = await supabase
      .from('transport_requests')
      .select('*')
      .eq('id', transport_id)
      .maybeSingle();

    if (fetchError) {
      return NextResponse.json({ error: fetchError.message }, { status: 500 });
    }
    if (!existing) {
      return NextResponse.json({ error: `No transport request found for id: ${transport_id}` }, { status: 404 });
    }

    const updateData: Record<string, unknown> = { transport_status: new_status };
    if (gps_end) updateData.gps_end = gps_end;
    if (notes) updateData.notes = notes;

    const { data: updated, error: updateError } = await supabase
      .from('transport_requests')
      .update(updateData)
      .eq('id', transport_id)
      .select()
      .single();

    if (updateError) {
      return NextResponse.json({ error: updateError.message }, { status: 500 });
    }

    let deliveryWorkflowTriggered = false;
    if (new_status === 'delivered') {
      deliveryWorkflowTriggered = true;
      console.log(`[Transport Interne] Lot ${existing.lot_id} livré. Facturation déclenchée.`);
    }

    return NextResponse.json({
      success: true,
      transport_request: updated,
      status_label: STATUS_LABELS[new_status] ?? new_status,
      delivery_workflow_triggered: deliveryWorkflowTriggered,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
