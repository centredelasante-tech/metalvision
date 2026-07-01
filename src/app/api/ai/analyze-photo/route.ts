import { NextRequest, NextResponse } from 'next/server';
import { getChatCompletion } from '@/lib/ai/chatCompletion';
import { createClient } from '../../../../lib/supabase/server';

const METAL_DENSITIES: Record<string, number> = {
  aluminium: 2700,
  cuivre: 8960,
  laiton: 8500,
  acier: 7850,
  inox: 8000,
  fonte: 7200,
  mélange: 5000,
};

const METAL_ALIASES: Record<string, string> = {
  aluminum: 'aluminium',
  copper: 'cuivre',
  brass: 'laiton',
  steel: 'acier',
  'stainless steel': 'inox',
  stainless: 'inox',
  'cast iron': 'fonte',
  iron: 'fonte',
  mix: 'mélange',
  mixed: 'mélange',
  melange: 'mélange',
};

function normalizeMetal(raw: string): string {
  const lower = raw.toLowerCase().trim();
  return METAL_ALIASES[lower] ?? lower;
}

export async function POST(req: NextRequest) {
  try {
    const formData = await req.formData();
    const imageFile = formData.get('image') as File | null;
    const referenceSizeCm = parseFloat(formData.get('reference_size_cm') as string);
    const metalPricePerKg = parseFloat(formData.get('metal_price_per_kg') as string);
    const densityOverrideRaw = formData.get('density_override');
    const densityOverride = densityOverrideRaw ? parseFloat(densityOverrideRaw as string) : null;
    const clientId = formData.get('client_id') as string | null;

    if (!imageFile) {
      return NextResponse.json({ error: 'Image file is required' }, { status: 400 });
    }
    if (isNaN(referenceSizeCm) || referenceSizeCm <= 0) {
      return NextResponse.json({ error: 'reference_size_cm must be a positive number' }, { status: 400 });
    }
    if (isNaN(metalPricePerKg) || metalPricePerKg < 0) {
      return NextResponse.json({ error: 'metal_price_per_kg must be a non-negative number' }, { status: 400 });
    }

    // Convert image to base64 data URI
    const arrayBuffer = await imageFile.arrayBuffer();
    const base64 = Buffer.from(arrayBuffer).toString('base64');
    const mimeType = imageFile.type || 'image/jpeg';
    const base64DataUri = `data:${mimeType};base64,${base64}`;

    const systemPrompt = `Tu es un expert en analyse visuelle industrielle spécialisé dans les métaux recyclés.

OBJECTIF :
Analyser l'image fournie pour :
1. Identifier le type de métal visible.
2. Décrire l'état (propre, oxydé, mélangé, compacté).
3. Déterminer les dimensions approximatives du tas en utilisant la référence d'échelle fournie.
4. Calculer le volume estimé.
5. Calculer le poids estimé selon la densité du métal.
6. Calculer la valeur estimée selon le prix du marché fourni.

RÉFÉRENCE D'ÉCHELLE : Une référence physique visible dans l'image a une taille réelle de ${referenceSizeCm} cm.
Utilise-la pour convertir les dimensions relatives en dimensions réelles.

ÉTAPES D'ANALYSE :

1. IDENTIFICATION DU MÉTAL
Analyse la texture, la couleur, la brillance, l'oxydation et la forme.
Choisis parmi : aluminium, cuivre, laiton, acier, inox, fonte, mélange.
Donne un niveau de confiance entre 0 et 1.

2. DIMENSIONS
Estime :
- largeur du tas (cm)
- hauteur du tas (cm)
- profondeur du tas (cm)

3. VOLUME
Utilise la formule :
volume_m3 = (largeur_cm / 100) * (profondeur_cm / 100) * (hauteur_cm / 100) * 0.65
(0.65 = coefficient de compaction standard)

4. DENSITÉ
${densityOverride ? `density_override fourni : utilise ${densityOverride} kg/m3` : `Utilise les densités standards :
- aluminium : 2700 kg/m3
- cuivre : 8960 kg/m3
- laiton : 8500 kg/m3
- acier : 7850 kg/m3
- inox : 8000 kg/m3
- fonte : 7200 kg/m3
- mélange : 5000 kg/m3`}

5. POIDS
weight_kg = volume_m3 * densité

6. VALEUR
estimated_value = weight_kg * ${metalPricePerKg} (prix du marché fourni en $/kg)

FORMAT DE SORTIE (JSON STRICT) :
{
  "metal_type": "...",
  "confidence": 0.00,
  "width_cm": 0,
  "height_cm": 0,
  "depth_cm": 0,
  "volume_m3": 0,
  "weight_kg": 0,
  "estimated_value": 0,
  "compaction_visual": 0.00,
  "purity_visual": 0.00,
  "object_type": "...",
  "explanation": "..."
}

IMPORTANT : Réponds UNIQUEMENT avec l'objet JSON — aucun markdown, aucun bloc de code, aucun texte supplémentaire.`;

    const userPrompt = `Analyse cette photo de métal.

La référence d'échelle visible dans l'image mesure ${referenceSizeCm} cm dans la réalité.
Prix du marché : ${metalPricePerKg} $/kg.${densityOverride ? `\nDensité imposée : ${densityOverride} kg/m3.` : ''}

Effectue l'analyse complète et retourne uniquement le JSON demandé.`;

    const aiResponse = await getChatCompletion(
      'GEMINI',
      'gemini/gemini-2.5-flash',
      [
        { role: 'system', content: systemPrompt },
        {
          role: 'user',
          content: [
            { type: 'text', text: userPrompt },
            { type: 'image_url', image_url: { url: base64DataUri } },
          ],
        },
      ],
      { temperature: 0.2, max_tokens: 2048 }
    );

    const rawContent = aiResponse?.choices?.[0]?.message?.content ?? '';

    // Strip all possible markdown artifacts
    let jsonStr = rawContent
      .replace(/^`+(?:json)?\s*/i, '')
      .replace(/\s*`+$/, '')
      .trim();

    // If the string starts with { or [, extract just the JSON object
    const jsonStart = jsonStr.indexOf('{');
    const jsonEnd = jsonStr.lastIndexOf('}');
    if (jsonStart !== -1 && jsonEnd !== -1 && jsonEnd > jsonStart) {
      jsonStr = jsonStr.slice(jsonStart, jsonEnd + 1);
    }

    let parsed: {
      metal_type: string;
      confidence: number;
      width_cm: number;
      height_cm: number;
      depth_cm: number;
      volume_m3: number;
      weight_kg: number;
      estimated_value: number;
      compaction_visual?: number;
      purity_visual?: number;
      object_type?: string;
      explanation: string;
    };

    try {
      parsed = JSON.parse(jsonStr);
    } catch {
      return NextResponse.json(
        { error: 'Failed to parse AI response', details: rawContent },
        { status: 500 }
      );
    }

    const metalType = normalizeMetal(parsed.metal_type);
    const widthCm = Math.max(0, parsed.width_cm ?? 0);
    const heightCm = Math.max(0, parsed.height_cm ?? 0);
    const depthCm = Math.max(0, parsed.depth_cm ?? 0);

    // Volume in m³ with compaction coefficient 0.65
    const volumeM3 = parsed.volume_m3 ?? ((widthCm / 100) * (depthCm / 100) * (heightCm / 100) * 0.65);

    // Density in kg/m³
    const density = densityOverride ?? METAL_DENSITIES[metalType] ?? 5000;

    // Weight in kg
    const weightKg = parsed.weight_kg ?? (volumeM3 * density);

    // Estimated value
    const estimatedValue = parsed.estimated_value ?? (weightKg * metalPricePerKg);

    // Confidence: 0-1
    const confidence = Math.min(1, Math.max(0, parsed.confidence ?? 0));

    const compactionVisual = Math.min(1, Math.max(0, parsed.compaction_visual ?? 0.65));
    const purityVisual = Math.min(1, Math.max(0, parsed.purity_visual ?? 0.5));
    const objectType = parsed.object_type ?? null;

    const result = {
      metal_type: metalType,
      confidence: Math.round(confidence * 100) / 100,
      width_cm: Math.round(widthCm * 10) / 10,
      height_cm: Math.round(heightCm * 10) / 10,
      depth_cm: Math.round(depthCm * 10) / 10,
      volume_m3: Math.round(volumeM3 * 10000) / 10000,
      weight_kg: Math.round(weightKg * 100) / 100,
      estimated_value: Math.round(estimatedValue * 100) / 100,
      compaction_visual: Math.round(compactionVisual * 100) / 100,
      purity_visual: Math.round(purityVisual * 100) / 100,
      object_type: objectType,
      explanation: parsed.explanation ?? '',
    };

    // Store in raw_measurements if client_id is provided
    let measurementId: string | null = null;
    if (clientId) {
      try {
        const supabase = await createClient();
        const { data: insertedRow, error: dbError } = await supabase
          .from('raw_measurements')
          .insert({
            client_id: clientId,
            metal_type_predicted: result.metal_type,
            confidence: result.confidence,
            width_cm: result.width_cm,
            height_cm: result.height_cm,
            depth_cm: result.depth_cm,
            volume_estimated_m3: result.volume_m3,
            compaction_visual: result.compaction_visual,
            purity_visual: result.purity_visual,
            object_type: result.object_type,
            raw_analysis_json: parsed,
            reference_size_cm: referenceSizeCm,
            metal_price_per_kg: metalPricePerKg,
            density_override: densityOverride,
          })
          .select('id')
          .single();

        if (!dbError && insertedRow) {
          measurementId = insertedRow.id;
        }
      } catch {
        // DB storage failure is non-blocking — analysis result is still returned
      }
    }

    return NextResponse.json({
      ...result,
      measurement_id: measurementId,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Internal server error';
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
