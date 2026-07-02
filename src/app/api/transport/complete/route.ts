import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

// ADEME emission factors (kgCO2e/tkm)
const EMISSION_FACTORS: Record<string, number> = {
  camion: 0.062,
  train: 0.0028,
  navire: 0.0115,
};

// Baseline = same trip by diesel truck
const BASELINE_EMISSION_FACTOR = 0.062;

async function geocodeAddress(address: string, apiKey: string): Promise<{ lat: number; lng: number }> {
  const url = `https://api.openrouteservice.org/geocode/search?api_key=${encodeURIComponent(apiKey)}&text=${encodeURIComponent(address)}&boundary.country=CA&size=1`;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Geocoding failed for address "${address}": ${response.statusText}`);
  }
  const data = await response.json();
  const feature = data?.features?.[0];
  if (!feature) {
    throw new Error(`No geocoding result found for address "${address}"`);
  }
  const [lng, lat] = feature.geometry.coordinates as [number, number];
  return { lat, lng };
}

async function calculateDistance(
  origin: { lat: number; lng: number },
  destination: { lat: number; lng: number },
  apiKey: string
): Promise<number> {
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
    throw new Error(`Distance calculation failed: ${response.statusText}`);
  }
  const data = await response.json();
  const distanceMeters: number = data?.routes?.[0]?.summary?.distance;
  if (distanceMeters == null) {
    throw new Error('No distance returned from OpenRouteService');
  }
  return distanceMeters / 1000;
}

export async function POST(request: NextRequest): Promise<NextResponse> {
  try {
    const body = await request.json();
    const { transport_request_id } = body as { transport_request_id: string };

    if (!transport_request_id || typeof transport_request_id !== 'string') {
      return NextResponse.json(
        { error: 'transport_request_id is required and must be a string' },
        { status: 400 }
      );
    }

    const supabase = await createClient();

    // Step 1: Fetch the transport request
    const { data: transportRequest, error: fetchError } = await supabase
      .from('transport_requests')
      .select('id, lot_id, pickup_address, dropoff_address, transport_mode, weight_tonnes, company_id, distance_km, ghg_transport_kgco2e, emission_factor_used')
      .eq('id', transport_request_id)
      .single();

    if (fetchError || !transportRequest) {
      return NextResponse.json(
        { error: fetchError?.message ?? 'Transport request not found' },
        { status: 404 }
      );
    }

    let distance_km: number = transportRequest.distance_km;
    let ghg_transport_kgco2e: number = transportRequest.ghg_transport_kgco2e;
    let emission_factor_used: number = transportRequest.emission_factor_used;

    // Step 2: Calculate distance if not already stored
    if (distance_km == null) {
      const apiKey = process.env.OPENROUTESERVICE_API_KEY ?? '';

      try {
        const originCoords = await geocodeAddress(transportRequest.pickup_address, apiKey);
        const destinationCoords = await geocodeAddress(transportRequest.dropoff_address, apiKey);
        distance_km = await calculateDistance(originCoords, destinationCoords, apiKey);
      } catch (geoError: unknown) {
        const message = geoError instanceof Error ? geoError.message : 'Failed to calculate distance';
        return NextResponse.json({ error: message }, { status: 502 });
      }

      const weight_tonnes: number = transportRequest.weight_tonnes ?? 0;
      const transport_mode: string = transportRequest.transport_mode ?? 'camion';
      emission_factor_used = EMISSION_FACTORS[transport_mode] ?? EMISSION_FACTORS['camion'];
      ghg_transport_kgco2e = distance_km * weight_tonnes * emission_factor_used;

      // Update transport_requests with calculated values
      const { error: updateDistanceError } = await supabase
        .from('transport_requests')
        .update({
          distance_km,
          ghg_transport_kgco2e,
          emission_factor_used,
        })
        .eq('id', transport_request_id);

      if (updateDistanceError) {
        return NextResponse.json(
          { error: `Failed to update distance data: ${updateDistanceError.message}` },
          { status: 500 }
        );
      }
    }

    // Step 3: Update transport_status = 'delivered'
    const { error: statusError } = await supabase
      .from('transport_requests')
      .update({ transport_status: 'delivered' })
      .eq('id', transport_request_id);

    if (statusError) {
      return NextResponse.json(
        { error: `Failed to update transport status: ${statusError.message}` },
        { status: 500 }
      );
    }

    // Step 4: Find active project for this company
    const { data: activeProject, error: projectError } = await supabase
      .from('projects')
      .select('id')
      .eq('client_id', transportRequest.company_id)
      .eq('status', 'active')
      .single();

    if (projectError && projectError.code !== 'PGRST116') {
      // PGRST116 = no rows found — not an error, just no active project
      return NextResponse.json(
        { error: `Failed to fetch active project: ${projectError.message}` },
        { status: 500 }
      );
    }

    let activity_log_id: string | null = null;

    // Step 5: Insert into project_activity_logs if active project exists
    if (activeProject) {
      const weight_tonnes: number = transportRequest.weight_tonnes ?? 0;
      const transport_mode: string = transportRequest.transport_mode ?? 'camion';

      const projectEmissionFactor = EMISSION_FACTORS[transport_mode] ?? EMISSION_FACTORS['camion'];

      const ghg_emissions_baseline_kgco2e = distance_km * weight_tonnes * BASELINE_EMISSION_FACTOR;
      const ghg_emissions_project_kgco2e = distance_km * weight_tonnes * projectEmissionFactor;
      const ghg_reduction_kgco2e = ghg_emissions_baseline_kgco2e - ghg_emissions_project_kgco2e;

      // Get current authenticated user
      const { data: { user } } = await supabase.auth.getUser();

      const { data: activityLog, error: logError } = await supabase
        .from('project_activity_logs')
        .insert({
          project_id: activeProject.id,
          activity_type: 'transport',
          related_transport_request_id: transport_request_id,
          ghg_emissions_baseline_kgco2e,
          ghg_emissions_project_kgco2e,
          ghg_reduction_kgco2e,
          uncertainty_percent: 6.2,
          actor_id: user?.id ?? null,
          timestamp: new Date().toISOString(),
        })
        .select('id')
        .single();

      if (logError) {
        return NextResponse.json(
          { error: `Failed to insert activity log: ${logError.message}` },
          { status: 500 }
        );
      }

      activity_log_id = activityLog?.id ?? null;
    }

    // Step 6: Return success
    return NextResponse.json({
      success: true,
      distance_km,
      ghg_transport_kgco2e,
      activity_log_id,
    });
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
