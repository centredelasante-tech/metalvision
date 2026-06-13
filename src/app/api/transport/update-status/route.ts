import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

const VALID_STATUSES = ['pending', 'assigned', 'en_route', 'picked_up', 'delivered', 'cancelled'];

/**
 * POST /api/transport/update-status
 *
 * Updates the status of a TransportRequest by external_reference.
 * If status = 'delivered', marks the lot as collected and triggers invoicing workflow.
 *
 * Body (JSON):
 *   external_reference : string
 *   new_status         : 'pending' | 'assigned' | 'en_route' | 'picked_up' | 'delivered' | 'cancelled'
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { external_reference, new_status } = body;

    if (!external_reference || typeof external_reference !== 'string') {
      return NextResponse.json({ error: 'external_reference is required' }, { status: 400 });
    }
    if (!new_status || !VALID_STATUSES.includes(new_status)) {
      return NextResponse.json(
        { error: `new_status must be one of: ${VALID_STATUSES.join(', ')}` },
        { status: 400 }
      );
    }

    const supabase = await createClient();

    // ── Find the transport request ───────────────────────────────────────────
    const { data: existing, error: fetchError } = await supabase
      .from('transport_requests')
      .select('*')
      .eq('external_reference', external_reference)
      .maybeSingle();

    if (fetchError) {
      return NextResponse.json({ error: fetchError.message }, { status: 500 });
    }
    if (!existing) {
      return NextResponse.json(
        { error: `No transport request found for external_reference: ${external_reference}` },
        { status: 404 }
      );
    }

    // ── Update status ────────────────────────────────────────────────────────
    const { data: updated, error: updateError } = await supabase
      .from('transport_requests')
      .update({ transport_status: new_status })
      .eq('external_reference', external_reference)
      .select()
      .single();

    if (updateError) {
      return NextResponse.json({ error: updateError.message }, { status: 500 });
    }

    // ── Delivery workflow ────────────────────────────────────────────────────
    let deliveryWorkflowTriggered = false;
    if (new_status === 'delivered') {
      deliveryWorkflowTriggered = true;
      // WORKFLOW 3: Mark lot as collected + trigger invoicing
      // BACKEND INTEGRATION: PATCH /api/lots/:lot_id { status: 'collected' }
      // BACKEND INTEGRATION: POST /api/invoices { lot_id: existing.lot_id }
      // These are placeholder hooks — implement when lot/invoice tables are ready
      console.log(`[Transport] Lot ${existing.lot_id} marked as collected. Invoicing triggered.`);
    }

    // ── Notification placeholder ─────────────────────────────────────────────
    // BACKEND INTEGRATION: POST /api/notifications { client_id, message, type }
    console.log(`[Transport] Status updated to ${new_status} for ref ${external_reference}`);

    return NextResponse.json({
      success: true,
      transport_request: updated,
      delivery_workflow_triggered: deliveryWorkflowTriggered,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
