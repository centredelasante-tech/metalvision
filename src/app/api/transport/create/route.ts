import { NextRequest, NextResponse } from 'next/server';

/**
 * POST /api/transport/create
 *
 * DEPRECATED: External Groupe Robert transport has been replaced by internal transport.
 * Redirects to /api/transport/internal-create for backward compatibility.
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const baseUrl = process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000';

    const res = await fetch(`${baseUrl}/api/transport/internal-create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...body, provider: 'internal' }),
    });

    const data = await res.json();
    return NextResponse.json(data, { status: res.status });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
