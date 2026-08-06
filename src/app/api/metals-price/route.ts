import { NextResponse } from 'next/server';

export const revalidate = 600; // 10-minute ISR cache

interface MetalEntry {
  label: string;
  symbol: string | null; // null = not available in API
  price: number | null;
  trend: 'up' | 'down' | 'neutral';
  available: boolean;
}

interface CachedData {
  prices: Record<string, number>;
  fetchedAt: number;
}

// In-memory cache for trend comparison (previous fetch prices)
let previousCache: CachedData | null = null;
let currentCache: CachedData | null = null;

// Metals we want to display
// NOTE: 'iron' and 'steel' are NOT available in the Metals.Dev API.
// Available industrial metals: copper, aluminum, lead, nickel, zinc
const METALS_CONFIG: Array<{ label: string; symbol: string | null }> = [
  { label: 'Fer',       symbol: null },       // Not available in Metals.Dev API
  { label: 'Cuivre',   symbol: 'copper' },    // Available: Spot Copper (mt)
  { label: 'Aluminium',symbol: 'aluminum' },  // Available: Spot Aluminum (mt)
  { label: 'Acier',    symbol: null },        // Not available in Metals.Dev API
];

function calcTrend(
  symbol: string,
  currentPrices: Record<string, number>,
  prevPrices: Record<string, number> | null
): 'up' | 'down' | 'neutral' {
  if (!prevPrices || prevPrices[symbol] === undefined) return 'neutral';
  const curr = currentPrices[symbol];
  const prev = prevPrices[symbol];
  if (curr > prev) return 'up';
  if (curr < prev) return 'down';
  return 'neutral';
}

export async function GET() {
  const apiKey = process.env.METALS_API_KEY;

  if (!apiKey) {
    return NextResponse.json(
      { error: 'METALS_API_KEY not configured' },
      { status: 500 }
    );
  }

  try {
    const url = `https://api.metals.dev/v1/latest?api_key=${apiKey}&currency=CAD&unit=kg`;
    const res = await fetch(url, { next: { revalidate: 600 } });

    if (!res.ok) {
      throw new Error(`Metals.Dev API returned ${res.status}`);
    }

    const data = await res.json();

    if (data.status !== 'success') {
      throw new Error(data.error_message ?? 'Unknown API error');
    }

    const apiMetals: Record<string, number> = data.metals ?? {};

    // Rotate cache for trend comparison
    if (currentCache) {
      previousCache = currentCache;
    }
    currentCache = {
      prices: apiMetals,
      fetchedAt: Date.now(),
    };

    const result: MetalEntry[] = METALS_CONFIG.map(({ label, symbol }) => {
      if (symbol === null) {
        // Metal not available in API — report clearly
        return {
          label,
          symbol: null,
          price: null,
          trend: 'neutral' as const,
          available: false,
        };
      }

      const price = apiMetals[symbol] ?? null;
      const trend = price !== null
        ? calcTrend(symbol, apiMetals, previousCache?.prices ?? null)
        : 'neutral';

      return {
        label,
        symbol,
        price,
        trend,
        available: price !== null,
      };
    });

    return NextResponse.json(
      { metals: result, currency: 'CAD', unit: 'kg', timestamp: data.timestamps?.metal ?? new Date().toISOString() },
      {
        headers: {
          'Cache-Control': 'public, s-maxage=600, stale-while-revalidate=60',
        },
      }
    );
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Fetch failed';
    return NextResponse.json({ error: message }, { status: 502 });
  }
}
