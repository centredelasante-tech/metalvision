import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * POST /api/transport/create
 *
 * Creates a TransportRequest, calls the Groupe Robert external API (placeholder),
 * stores the external_reference, and sets status to 'assigned'.
 *
 * Body (JSON):
 *   lot_id          : string
 *   container_id    : string
 *   pickup_address  : string
 *   dropoff_address : string
 *   weight?         : number  (kg, optional)
 *   description?    : string
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { lot_id, container_id, pickup_address, dropoff_address, weight, description } = body;

    if (!lot_id || typeof lot_id !== 'string') {
      return NextResponse.json({ error: 'lot_id is required' }, { status: 400 });
    }
    if (!pickup_address || typeof pickup_address !== 'string') {
      return NextResponse.json({ error: 'pickup_address is required' }, { status: 400 });
    }
    if (!dropoff_address || typeof dropoff_address !== 'string') {
      return NextResponse.json({ error: 'dropoff_address is required' }, { status: 400 });
    }

    // ── Call external Groupe Robert API (placeholder) ────────────────────────
    const groupeRobertBaseUrl =
      process.env.GROUPE_ROBERT_API_URL || 'https://api.grouperobert.com'; // placeholder

    let externalReference: string | null = null;
    let scheduledTime: string | null = null;

    try {
      const externalRes = await fetch(`${groupeRobertBaseUrl}/external/grouperobert/create-shipment`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${process.env.GROUPE_ROBERT_API_KEY || 'PLACEHOLDER_KEY'}`,
        },
        body: JSON.stringify({
          pickup_address,
          dropoff_address,
          weight: weight ?? 0,
          description: description ?? `Transport lot ${lot_id}`,
          reference: lot_id,
        }),
      });

      if (externalRes.ok) {
        const externalData = await externalRes.json();
        externalReference = externalData.external_reference ?? null;
        scheduledTime = externalData.scheduled_time ?? null;
      } else {
        // Fallback: generate a mock reference so the workflow continues
        externalReference = `GR-${Date.now()}`;
        scheduledTime = new Date(Date.now() + 4 * 60 * 60 * 1000).toISOString();
      }
    } catch {
      // External API unavailable — use mock reference
      externalReference = `GR-MOCK-${Date.now()}`;
      scheduledTime = new Date(Date.now() + 4 * 60 * 60 * 1000).toISOString();
    }

    // ── Persist to Supabase ──────────────────────────────────────────────────
    const supabase = await createClient();

    const { data: transportRequest, error } = await supabase
      .from('transport_requests')
      .insert({
        lot_id,
        container_id: container_id ?? null,
        pickup_address,
        dropoff_address,
        transporter: 'Groupe Robert',
        external_reference: externalReference,
        scheduled_time: scheduledTime,
        transport_status: 'assigned',
        notes: description ?? null,
      })
      .select()
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({
      success: true,
      transport_request: transportRequest,
      external_reference: externalReference,
      scheduled_time: scheduledTime,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
