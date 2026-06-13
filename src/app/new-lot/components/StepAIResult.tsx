'use client';
import React, { useState, useEffect, useRef } from 'react';
import Icon from '@/components/ui/AppIcon';
import MetalBadge from '@/components/ui/MetalBadge';
import { LotDraft } from './NewLotWizard';

const METAL_PRICES: Record<string, number> = {
  fer: 0.27,
  acier: 0.35,
  aluminium: 2.72,
  cuivre: 10.90,
  laiton: 7.05,
  inox: 1.76,
};

interface AIAnalysisResult {
  metal_type: string;
  confidence: number;
  width_cm: number;
  height_cm: number;
  depth_cm: number;
  volume_m3: number;
  weight_kg: number;
  estimated_value: number;
  explanation: string;
}

interface Props {
  draft: LotDraft;
  updateDraft: (u: Partial<LotDraft>) => void;
  onNext: () => void;
  onBack: () => void;
}

type AnalysisState = 'loading' | 'done' | 'error';

export default function StepAIResult({ draft, updateDraft, onNext, onBack }: Props) {
  const [state, setState] = useState<AnalysisState>('loading');
  const [progress, setProgress] = useState(0);
  const [selectedMetal, setSelectedMetal] = useState('');
  const [volumeOverride, setVolumeOverride] = useState('');
  const [aiResult, setAiResult] = useState<AIAnalysisResult | null>(null);
  const [errorMessage, setErrorMessage] = useState('');
  const hasCalled = useRef(false);

  useEffect(() => {
    if (hasCalled.current) return;
    hasCalled.current = true;

    // Animate progress bar while waiting for API
    const progressInterval = setInterval(() => {
      setProgress((p) => {
        if (p >= 90) {
          clearInterval(progressInterval);
          return 90;
        }
        return p + 3;
      });
    }, 120);

    const runAnalysis = async () => {
      try {
        let imageFile: File | null = draft.photoFile ?? null;

        // If no real file (e.g. simulated capture), fetch the URL as a blob
        if (!imageFile && draft.photoUrl) {
          try {
            const res = await fetch(draft.photoUrl);
            const blob = await res.blob();
            imageFile = new File([blob], 'photo.jpg', { type: blob.type || 'image/jpeg' });
          } catch {
            // If fetch fails (CORS etc.), proceed without image — API will return error
          }
        }

        if (!imageFile) {
          throw new Error('Aucune image disponible pour l\'analyse.');
        }

        const formData = new FormData();
        formData.append('image', imageFile);
        formData.append('reference_size_cm', String(draft.referenceSizeCm || 10));
        formData.append('metal_price_per_kg', String(draft.metalPricePerKg || 0));
        if (draft.densityOverride != null) {
          formData.append('density_override', String(draft.densityOverride));
        }

        const response = await fetch('/api/ai/analyze-photo', {
          method: 'POST',
          body: formData,
        });

        const data = await response.json();

        if (!response.ok) {
          throw new Error(data.error || 'Erreur lors de l\'analyse IA');
        }

        clearInterval(progressInterval);
        setProgress(100);

        const result = data as AIAnalysisResult;
        setAiResult(result);
        setSelectedMetal(result.metal_type);
        setVolumeOverride(result.volume_m3.toString());

        updateDraft({
          metalType: result.metal_type,
          volumeEstimated: result.volume_m3,
          confidence: result.confidence,
          priceEstimated: result.estimated_value,
          widthCm: result.width_cm,
          heightCm: result.height_cm,
          depthCm: result.depth_cm,
          weightKg: result.weight_kg,
          aiExplanation: result.explanation,
        });

        setState('done');
      } catch (err: unknown) {
        clearInterval(progressInterval);
        setErrorMessage(err instanceof Error ? err.message : 'Erreur inconnue');
        setState('error');
      }
    };

    runAnalysis();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const recalcPrice = (metal: string, vol: number) => {
    const pricePerKg = draft.metalPricePerKg || (METAL_PRICES[metal] ?? 0.27);
    const density = draft.densityOverride ?? 7850;
    const weightKg = vol * density;
    const price = weightKg * pricePerKg;
    updateDraft({ priceEstimated: Math.round(price * 100) / 100, weightKg });
  };

  const handleMetalChange = (metal: string) => {
    setSelectedMetal(metal);
    updateDraft({ metalType: metal });
    recalcPrice(metal, parseFloat(volumeOverride) || draft.volumeEstimated);
  };

  const handleVolumeChange = (val: string) => {
    setVolumeOverride(val);
    const v = parseFloat(val);
    if (!isNaN(v)) {
      updateDraft({ volumeEstimated: v });
      recalcPrice(selectedMetal, v);
    }
  };

  if (state === 'loading') {
    return (
      <div className="bg-card rounded-xl border border-border p-8 flex flex-col items-center gap-6">
        <div className="relative w-20 h-20">
          <div className="absolute inset-0 rounded-full border-4 border-muted" />
          <div
            className="absolute inset-0 rounded-full border-4 border-primary border-t-transparent animate-spin"
            style={{ animationDuration: '0.8s' }}
          />
          <div className="absolute inset-0 flex items-center justify-center">
            <Icon name="SparklesIcon" size={28} className="text-primary" />
          </div>
        </div>
        <div className="text-center">
          <h3 className="text-base font-600 text-foreground">Analyse IA en cours...</h3>
          <p className="text-sm text-muted-foreground mt-1">
            Gemini Vision identifie le métal et calcule le volume estimé
          </p>
        </div>
        <div className="w-full">
          <div className="flex justify-between text-xs text-muted-foreground mb-2">
            <span>Traitement de l'image</span>
            <span className="tabular-nums">{progress}%</span>
          </div>
          <div className="h-2 bg-muted rounded-full overflow-hidden">
            <div
              className="h-full bg-primary rounded-full confidence-bar-fill transition-all duration-300"
              style={{ width: `${progress}%` }}
            />
          </div>
          <div className="mt-3 space-y-1">
            {[
              { label: 'Extraction des caractéristiques visuelles', done: progress > 25 },
              { label: 'Classification du type de métal', done: progress > 55 },
              { label: 'Estimation volumétrique', done: progress > 80 },
              { label: 'Calcul du prix de marché', done: progress > 95 },
            ].map((step) => (
              <div key={`ai-step-${step.label}`} className="flex items-center gap-2">
                <div className={`w-4 h-4 rounded-full flex items-center justify-center flex-shrink-0 ${step.done ? 'bg-primary' : 'bg-muted'}`}>
                  {step.done && <Icon name="CheckIcon" size={10} className="text-primary-foreground" />}
                </div>
                <span className={`text-xs ${step.done ? 'text-foreground' : 'text-muted-foreground'}`}>
                  {step.label}
                </span>
              </div>
            ))}
          </div>
        </div>
      </div>
    );
  }

  if (state === 'error') {
    return (
      <div className="bg-card rounded-xl border border-red-200 bg-red-50 p-8 text-center">
        <Icon name="ExclamationTriangleIcon" size={40} className="text-red-500 mx-auto mb-4" />
        <h3 className="text-base font-600 text-foreground">Analyse IA échouée</h3>
        <p className="text-sm text-muted-foreground mt-2 mb-2">
          Impossible d'analyser la photo. Vérifiez la qualité de l'image et réessayez.
        </p>
        {errorMessage && (
          <p className="text-xs text-red-500 mb-5 px-4">{errorMessage}</p>
        )}
        <button onClick={onBack} className="btn-primary px-6 py-2.5 rounded-lg text-sm font-600">
          Reprendre une photo
        </button>
      </div>
    );
  }

  if (!aiResult) return null;

  return (
    <div className="space-y-4 fade-in-up">
      {/* AI Result Card */}
      <div className="bg-card rounded-xl border border-primary/20 overflow-hidden">
        <div className="flex items-center gap-3 px-5 py-4 bg-secondary border-b border-primary/20">
          <Icon name="SparklesIcon" size={18} className="text-primary" />
          <h3 className="text-sm font-600 text-primary">Résultat de l'analyse IA — Gemini Vision</h3>
          <div className="ml-auto flex items-center gap-1.5 bg-primary/10 px-2.5 py-1 rounded-full">
            <div className="w-1.5 h-1.5 bg-primary rounded-full" />
            <span className="text-xs font-600 text-primary">Confiance {aiResult.confidence}%</span>
          </div>
        </div>

        <div className="p-5 space-y-5">
          {/* Main result */}
          <div className="grid grid-cols-3 gap-4">
            <div className="text-center p-4 bg-muted rounded-xl">
              <p className="text-[11px] font-600 uppercase tracking-wide text-muted-foreground mb-2">Type détecté</p>
              <MetalBadge metal={aiResult.metal_type} />
            </div>
            <div className="text-center p-4 bg-muted rounded-xl">
              <p className="text-[11px] font-600 uppercase tracking-wide text-muted-foreground mb-2">Volume est.</p>
              <p className="text-xl font-700 tabular-nums text-foreground">
                {aiResult.volume_m3.toFixed(4)}
                <span className="text-sm font-500 text-muted-foreground ml-1">m³</span>
              </p>
            </div>
            <div className="text-center p-4 bg-secondary rounded-xl">
              <p className="text-[11px] font-600 uppercase tracking-wide text-muted-foreground mb-2">Prix estimé</p>
              <p className="text-xl font-700 tabular-nums text-primary">
                {draft.priceEstimated.toFixed(2)}
                <span className="text-sm font-500 text-primary ml-1">$CA</span>
              </p>
            </div>
          </div>

          {/* Dimensions & Weight */}
          <div className="grid grid-cols-4 gap-3">
            <div className="text-center p-3 bg-muted rounded-lg">
              <p className="text-[10px] font-600 uppercase tracking-wide text-muted-foreground mb-1">Largeur</p>
              <p className="text-sm font-700 tabular-nums text-foreground">{aiResult.width_cm} <span className="text-xs font-400">cm</span></p>
            </div>
            <div className="text-center p-3 bg-muted rounded-lg">
              <p className="text-[10px] font-600 uppercase tracking-wide text-muted-foreground mb-1">Hauteur</p>
              <p className="text-sm font-700 tabular-nums text-foreground">{aiResult.height_cm} <span className="text-xs font-400">cm</span></p>
            </div>
            <div className="text-center p-3 bg-muted rounded-lg">
              <p className="text-[10px] font-600 uppercase tracking-wide text-muted-foreground mb-1">Profondeur</p>
              <p className="text-sm font-700 tabular-nums text-foreground">{aiResult.depth_cm} <span className="text-xs font-400">cm</span></p>
            </div>
            <div className="text-center p-3 bg-secondary rounded-lg">
              <p className="text-[10px] font-600 uppercase tracking-wide text-muted-foreground mb-1">Poids est.</p>
              <p className="text-sm font-700 tabular-nums text-primary">{aiResult.weight_kg.toFixed(1)} <span className="text-xs font-400">kg</span></p>
            </div>
          </div>

          {/* Confidence bar */}
          <div>
            <div className="flex justify-between text-xs text-muted-foreground mb-1.5">
              <span>Niveau de confiance</span>
              <span className="tabular-nums font-600">{aiResult.confidence}%</span>
            </div>
            <div className="h-2.5 bg-muted rounded-full overflow-hidden">
              <div
                className={`h-full rounded-full confidence-bar-fill ${
                  aiResult.confidence >= 85 ? 'bg-primary' :
                  aiResult.confidence >= 70 ? 'bg-accent' : 'bg-red-500'
                }`}
                style={{ width: `${aiResult.confidence}%` }}
              />
            </div>
            {aiResult.confidence < 80 && (
              <p className="text-xs text-amber-600 mt-1.5 flex items-center gap-1">
                <Icon name="ExclamationTriangleIcon" size={12} />
                Confiance modérée — vérifiez le type de métal ci-dessous
              </p>
            )}
          </div>

          {/* AI Explanation */}
          {aiResult.explanation && (
            <div className="p-3 bg-muted rounded-lg">
              <p className="text-[11px] font-600 text-muted-foreground mb-1 uppercase tracking-wide">Explication IA</p>
              <p className="text-xs text-foreground leading-relaxed">{aiResult.explanation}</p>
            </div>
          )}
        </div>
      </div>

      {/* Correction form */}
      <div className="bg-card rounded-xl border border-border p-5">
        <h4 className="text-sm font-600 text-foreground mb-1">Corriger si nécessaire</h4>
        <p className="text-xs text-muted-foreground mb-4">
          L'IA peut se tromper. Ajustez le type de métal ou le volume si vous constatez une erreur.
        </p>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-xs font-600 text-foreground mb-1.5">Type de métal</label>
            <select
              value={selectedMetal}
              onChange={(e) => handleMetalChange(e.target.value)}
              className="w-full px-3 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            >
              {Object.keys(METAL_PRICES).map((m) => (
                <option key={`metal-option-${m}`} value={m}>
                  {m.charAt(0).toUpperCase() + m.slice(1)} — {METAL_PRICES[m].toFixed(2)} $CA/kg
                </option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-xs font-600 text-foreground mb-1.5">Volume estimé (m³)</label>
            <input
              type="number"
              step="0.0001"
              min="0"
              value={volumeOverride}
              onChange={(e) => handleVolumeChange(e.target.value)}
              className="w-full px-3 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm tabular-nums focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>
        </div>

        <div className="mt-4 p-3 bg-secondary rounded-lg flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Icon name="CurrencyDollarIcon" size={16} className="text-primary" />
            <span className="text-sm text-foreground">Prix recalculé</span>
          </div>
          <span className="text-lg font-700 tabular-nums text-primary">
            {draft.priceEstimated.toFixed(2)} $CA
          </span>
        </div>

        <p className="text-[11px] text-muted-foreground mt-2">
          Basé sur {draft.metalPricePerKg.toFixed(2)} $CA/kg × {aiResult.weight_kg.toFixed(1)} kg (poids estimé)
        </p>
      </div>

      {/* Actions */}
      <div className="flex gap-3">
        <button
          onClick={onBack}
          className="flex-1 py-3 rounded-xl text-sm font-600 border border-border text-foreground btn-ghost flex items-center justify-center gap-2"
        >
          <Icon name="ArrowLeftIcon" size={16} />
          Retour
        </button>
        <button
          onClick={onNext}
          className="flex-1 btn-primary py-3 rounded-xl text-sm font-600 flex items-center justify-center gap-2"
        >
          Confirmer et soumettre
          <Icon name="ArrowRightIcon" size={16} className="text-primary-foreground" />
        </button>
      </div>
    </div>
  );
}