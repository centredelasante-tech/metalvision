import { NextRequest, NextResponse } from 'next/server';

interface GeocodeResult {
  lng: number;
  lat: number;
}

interface DirectionsResult {
  distance_km: number;
}

async function geocodeAddress(address: string, apiKey: string): Promise<GeocodeResult> {
  const url = new URL('https://api.openrouteservice.org/geocode/search');
  url.searchParams.set('api_key', apiKey);
  url.searchParams.set('text', address);
  url.searchParams.set('boundary.country', 'CA');
  url.searchParams.set('size', '1');

  const response = await fetch(url.toString());

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Geocoding failed for "${address}": ${response.status} ${errorText}`);
  }

  const data = await response.json();

  if (!data.features || data.features.length === 0) {
    throw new Error(`No geocoding result found for address: "${address}"`);
  }

  const [lng, lat] = data.features[0].geometry.coordinates as [number, number];
  return { lng, lat };
}

async function calculateRoadDistance(
  origin: GeocodeResult,
  destination: GeocodeResult,
  apiKey: string
): Promise<DirectionsResult> {
  const response = await fetch('https://api.openrouteservice.org/v2/directions/driving-hgv', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: apiKey,
    },
    body: JSON.stringify({
      coordinates: [
        [origin.lng, origin.lat],
        [destination.lng, destination.lat],
      ],
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Directions API failed: ${response.status} ${errorText}`);
  }

  const data = await response.json();

  const distanceMeters: number = data?.routes?.[0]?.summary?.distance;
  if (typeof distanceMeters !== 'number') {
    throw new Error('Could not extract distance from OpenRouteService Directions response');
  }

  const distance_km = distanceMeters / 1000;
  return { distance_km };
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  try {
    const body = await request.json();
    const { pickup_address, dropoff_address, weight_kg } = body as {
      pickup_address: string;
      dropoff_address: string;
      weight_kg: number;
    };

    // Validate inputs
    if (!pickup_address || typeof pickup_address !== 'string') {
      return NextResponse.json({ error: 'pickup_address is required and must be a string' }, { status: 400 });
    }
    if (!dropoff_address || typeof dropoff_address !== 'string') {
      return NextResponse.json({ error: 'dropoff_address is required and must be a string' }, { status: 400 });
    }
    if (typeof weight_kg !== 'number' || weight_kg <= 0) {
      return NextResponse.json({ error: 'weight_kg is required and must be a positive number' }, { status: 400 });
    }

    const apiKey = process.env.OPENROUTESERVICE_API_KEY;
    if (!apiKey || apiKey === 'your-openrouteservice-api-key-here') {
      return NextResponse.json({ error: 'OPENROUTESERVICE_API_KEY is not configured' }, { status: 500 });
    }

    // Step 1: Geocode both addresses
    const [originCoords, destinationCoords] = await Promise.all([
      geocodeAddress(pickup_address, apiKey),
      geocodeAddress(dropoff_address, apiKey),
    ]);

    // Step 2: Calculate road distance
    const { distance_km } = await calculateRoadDistance(originCoords, destinationCoords, apiKey);

    // Step 3: Calculate GES emissions
    const weight_tonnes = weight_kg / 1000;
    const emission_factor = 0.062; // kgCO2e/tkm — facteur ADEME camion 20t
    const ghg_transport_kgco2e = distance_km * weight_tonnes * emission_factor;

    return NextResponse.json({
      distance_km: Math.round(distance_km * 100) / 100,
      weight_tonnes: Math.round(weight_tonnes * 10000) / 10000,
      ghg_transport_kgco2e: Math.round(ghg_transport_kgco2e * 10000) / 10000,
      emission_factor_used: emission_factor,
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
