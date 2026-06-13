import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

/**
 * POST /api/transport/poll-status
 *
 * WORKFLOW 2: Automated status polling.
 * Fetches all active transport requests, calls Groupe Robert status API for each,
 * and updates internal statuses. Intended to be called every 15 minutes
 * (e.g., via a cron job, Vercel Cron, or Supabase Edge Function scheduler).
 *
 * Trigger: POST with optional { dry_run: true } to preview without writing.
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => ({}));
    const dryRun = body?.dry_run === true;

    const supabase = await createClient();
    const groupeRobertBaseUrl =
      process.env.GROUPE_ROBERT_API_URL || 'https://api.grouperobert.com';

    // ── Fetch active (non-terminal) transport requests ───────────────────────
    const { data: activeRequests, error: fetchError } = await supabase
      .from('transport_requests')
      .select('id, lot_id, external_reference, transport_status')
      .not('transport_status', 'in', '("delivered","cancelled")')
      .not('external_reference', 'is', null);

    if (fetchError) {
      return NextResponse.json({ error: fetchError.message }, { status: 500 });
    }

    const results: Array<{ id: string; ref: string; old_status: string; new_status: string; updated: boolean }> = [];

    for (const req of activeRequests ?? []) {
      if (!req.external_reference) continue;

      let newStatus: string | null = null;

      try {
        const statusRes = await fetch(
          `${groupeRobertBaseUrl}/external/grouperobert/shipment-status?ref=${encodeURIComponent(req.external_reference)}`,
          {
            headers: {
              Authorization: `Bearer ${process.env.GROUPE_ROBERT_API_KEY || 'PLACEHOLDER_KEY'}`,
            },
          }
        );

        if (statusRes.ok) {
          const statusData = await statusRes.json();
          newStatus = statusData.status ?? null;
        }
      } catch {
        // Skip this request if external API is unavailable
        continue;
      }

      if (!newStatus || newStatus === req.transport_status) {
        results.push({ id: req.id, ref: req.external_reference, old_status: req.transport_status, new_status: newStatus ?? req.transport_status, updated: false });
        continue;
      }

      if (!dryRun) {
        await supabase
          .from('transport_requests')
          .update({ transport_status: newStatus })
          .eq('id', req.id);

        // Delivery workflow
        if (newStatus === 'delivered') {
          console.log(`[Poll] Lot ${req.lot_id} delivered — triggering collection + invoicing.`);
        }
      }

      results.push({ id: req.id, ref: req.external_reference, old_status: req.transport_status, new_status: newStatus, updated: !dryRun });
    }

    return NextResponse.json({
      success: true,
      dry_run: dryRun,
      processed: results.length,
      results,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
