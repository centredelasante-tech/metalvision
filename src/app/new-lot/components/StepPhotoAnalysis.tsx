'use client';
import React, { useState, useRef, useCallback } from 'react';
import Icon from '@/components/ui/AppIcon';
import { LotDraft, AIAnalysisResult } from './NewLotWizard';

const METAL_DENSITIES: Record<string, number> = {
  aluminium: 2700,
  cuivre: 8960,
  laiton: 8500,
  acier: 7850,
  inox: 8000,
  fonte: 7200,
  mélange: 5000,
};

// Compress image before upload
async function compressImage(file: File, maxWidthPx = 1280, quality = 0.82): Promise<File> {
  return new Promise((resolve) => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => {
      const canvas = document.createElement('canvas');
      let { width, height } = img;
      if (width > maxWidthPx) {
        height = Math.round((height * maxWidthPx) / width);
        width = maxWidthPx;
      }
      canvas.width = width;
      canvas.height = height;
      const ctx = canvas.getContext('2d');
      ctx?.drawImage(img, 0, 0, width, height);
      canvas.toBlob(
        (blob) => {
          URL.revokeObjectURL(url);
          resolve(blob ? new File([blob], file.name, { type: 'image/jpeg' }) : file);
        },
        'image/jpeg',
        quality
      );
    };
    img.src = url;
  });
}

interface Props {
  draft: LotDraft;
  updateDraft: (u: Partial<LotDraft>) => void;
  onNext: () => void;
  onBack: () => void;
}

type AnalysisState = 'idle' | 'compressing' | 'analyzing' | 'done' | 'error';

export default function StepPhotoAnalysis({ draft, updateDraft, onNext, onBack }: Props) {
  const [analysisState, setAnalysisState] = useState<AnalysisState>(
    draft.aiResult ? 'done' : 'idle'
  );
  const [errorMessage, setErrorMessage] = useState('');
  const [progress, setProgress] = useState(0);
  const fileRef = useRef<HTMLInputElement>(null);
  const cameraRef = useRef<HTMLInputElement>(null);

  const handleFileChange = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;
      setAnalysisState('compressing');
      try {
        const compressed = await compressImage(file);
        const url = URL.createObjectURL(compressed);
        updateDraft({ photoFile: compressed, photoUrl: url, aiResult: null });
        setAnalysisState('idle');
      } catch {
        setAnalysisState('idle');
      }
    },
    [updateDraft]
  );

  const handleRetake = () => {
    updateDraft({ photoFile: null, photoUrl: '', aiResult: null });
    setAnalysisState('idle');
    setErrorMessage('');
    setProgress(0);
  };

  const handleAnalyze = async () => {
    if (!draft.photoFile) return;
    setAnalysisState('analyzing');
    setErrorMessage('');
    setProgress(0);

    const progressInterval = setInterval(() => {
      setProgress((p) => {
        if (p >= 90) { clearInterval(progressInterval); return 90; }
        return p + 3;
      });
    }, 120);

    try {
      const formData = new FormData();
      formData.append('image', draft.photoFile);
      formData.append('reference_size_cm', String(draft.referenceSizeCm));
      formData.append('metal_price_per_kg', '0');

      const response = await fetch('/api/ai/analyze-photo', {
        method: 'POST',
        body: formData,
      });

      const data = await response.json();
      clearInterval(progressInterval);
      setProgress(100);

      if (!response.ok) {
        throw new Error(data.details ? `${data.error}: ${data.details}` : data.error || 'Erreur lors de l\'analyse IA');
      }

      const result = data as AIAnalysisResult;

      // Recalculate estimated_value client-side using local density map
      // (API receives metal_price_per_kg=0, so estimated_value from API is always 0)
      const density = METAL_DENSITIES[result.metal_type] ?? 5000;
      const weightKg = result.weight_kg > 0
        ? result.weight_kg
        : result.volume_m3 * density;
      const METAL_PRICES_CA: Record<string, number> = {
        fer: 0.27,
        cuivre: 10.90,
        aluminium: 2.72,
        acier: 0.35,
        laiton: 8.50,
        inox: 3.50,
        fonte: 0.27,
        mélange: 1.00,
      };

      const pricePerKg = METAL_PRICES_CA[result.metal_type] ?? 0;
      const estimatedValue = Math.round(weightKg * pricePerKg * 100) / 100;

      const correctedResult: AIAnalysisResult = {
        ...result,
        weight_kg: Math.round(weightKg * 100) / 100,
        estimated_value: estimatedValue,
      };

      updateDraft({
        aiResult: correctedResult,
        metalType: correctedResult.metal_type,
        volumeM3: correctedResult.volume_m3,
        weightKg: correctedResult.weight_kg,
      });
      setAnalysisState('done');
    } catch (err: unknown) {
      clearInterval(progressInterval);
      setErrorMessage(err instanceof Error ? err.message : 'Erreur inconnue');
      setAnalysisState('error');
    }
  };

  const handleRetry = () => {
    setAnalysisState('idle');
    setErrorMessage('');
    setProgress(0);
  };

  return (
    <div className="space-y-4">
      {/* Container info banner */}
      {draft.container && (
        <div className="flex items-center gap-3 p-3 bg-secondary border border-primary/20 rounded-xl">
          <Icon name="ArchiveBoxIcon" size={16} className="text-primary flex-shrink-0" />
          <div>
            <p className="text-xs text-muted-foreground">Conteneur sélectionné</p>
            <p className="text-sm font-700 text-foreground">{draft.container.name}</p>
          </div>
        </div>
      )}

      {/* Photo section */}
      <div className="bg-card rounded-xl border border-border p-5">
        <div className="flex items-center gap-2 mb-1">
          <Icon name="CameraIcon" size={18} className="text-primary" />
          <h3 className="text-base font-600 text-foreground">Photo du lot</h3>
        </div>
        <p className="text-sm text-muted-foreground mb-4">
          Prenez une photo claire du lot avec un objet de référence visible.
        </p>

        {/* Compressing state */}
        {analysisState === 'compressing' && (
          <div className="flex items-center justify-center gap-3 py-8">
            <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
            <p className="text-sm text-muted-foreground font-500">Compression de l'image…</p>
          </div>
        )}

        {/* No photo yet */}
        {analysisState !== 'compressing' && !draft.photoUrl && (
          <div className="flex flex-col gap-3">
            <button
              onClick={() => cameraRef.current?.click()}
              className="flex flex-col items-center gap-3 py-8 rounded-xl border-2 border-dashed border-border hover:border-primary hover:bg-secondary transition-all group min-h-[120px]"
            >
              <div className="w-16 h-16 rounded-full bg-muted group-hover:bg-primary/10 flex items-center justify-center transition-colors">
                <Icon name="CameraIcon" size={28} className="text-muted-foreground group-hover:text-primary" />
              </div>
              <div className="text-center">
                <p className="text-base font-600 text-foreground">Prendre une photo</p>
                <p className="text-sm text-muted-foreground mt-0.5">Caméra arrière du téléphone</p>
              </div>
            </button>
            <button
              onClick={() => fileRef.current?.click()}
              className="flex flex-col items-center gap-3 py-6 rounded-xl border-2 border-dashed border-border hover:border-primary hover:bg-secondary transition-all group min-h-[100px]"
            >
              <div className="w-14 h-14 rounded-full bg-muted group-hover:bg-primary/10 flex items-center justify-center transition-colors">
                <Icon name="PhotoIcon" size={24} className="text-muted-foreground group-hover:text-primary" />
              </div>
              <div className="text-center">
                <p className="text-base font-600 text-foreground">Importer une photo</p>
                <p className="text-sm text-muted-foreground mt-0.5">Depuis la galerie</p>
              </div>
            </button>
            {/* Camera input (mobile) */}
            <input
              ref={cameraRef}
              type="file"
              accept="image/*"
              // @ts-ignore
              capture="environment"
              className="hidden"
              onChange={handleFileChange}
            />
            {/* File picker (desktop/gallery) */}
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={handleFileChange}
            />
          </div>
        )}

        {/* Photo preview */}
        {analysisState !== 'compressing' && draft.photoUrl && (
          <div className="space-y-3">
            <div className="relative rounded-xl overflow-hidden bg-gray-100 w-full" style={{ aspectRatio: '4/3' }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={draft.photoUrl}
                alt="Aperçu de la photo du lot de métaux"
                className="w-full h-full object-cover"
              />
              {analysisState === 'done' && (
                <div className="absolute top-3 right-3 bg-primary/90 rounded-lg px-2.5 py-1 flex items-center gap-1.5">
                  <Icon name="CheckIcon" size={12} className="text-primary-foreground" />
                  <span className="text-xs font-600 text-primary-foreground">Analysée</span>
                </div>
              )}
            </div>
            {analysisState !== 'analyzing' && (
              <button
                onClick={handleRetake}
                className="w-full flex items-center justify-center gap-2 py-2.5 rounded-xl border border-border text-foreground font-600 text-sm btn-ghost min-h-[44px]"
              >
                <Icon name="ArrowPathIcon" size={16} />
                Reprendre la photo
              </button>
            )}
          </div>
        )}
      </div>

      {/* Reference size */}
      <div className="bg-card rounded-xl border border-border p-5">
        <label className="block text-sm font-600 text-foreground mb-1">
          Taille de référence (cm)
        </label>
        <p className="text-xs text-muted-foreground mb-3">
          Placez un objet de taille connue dans le champ (ex : règle de 30 cm).
        </p>
        <input
          type="number"
          min="1"
          step="1"
          value={draft.referenceSizeCm}
          onChange={(e) => updateDraft({ referenceSizeCm: parseFloat(e.target.value) || 30 })}
          className="w-full px-3 py-3 rounded-lg border border-border bg-input text-foreground text-base tabular-nums focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
        />
      </div>

      {/* Analyzing state */}
      {analysisState === 'analyzing' && (
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
            <h3 className="text-base font-600 text-foreground">Analyse en cours…</h3>
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
                className="h-full bg-primary rounded-full transition-all duration-300"
                style={{ width: `${progress}%` }}
              />
            </div>
          </div>
        </div>
      )}

      {/* Error state */}
      {analysisState === 'error' && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-5 text-center">
          <Icon name="ExclamationTriangleIcon" size={32} className="text-red-500 mx-auto mb-3" />
          <h3 className="text-sm font-600 text-foreground mb-1">Analyse échouée</h3>
          {errorMessage && (
            <p className="text-xs text-red-600 mb-4">{errorMessage}</p>
          )}
          <button
            onClick={handleRetry}
            className="btn-primary px-6 py-2.5 rounded-lg text-sm font-600"
          >
            Réessayer
          </button>
        </div>
      )}

      {/* Analyze button */}
      {(analysisState === 'idle' || analysisState === 'done') && draft.photoUrl && (
        <button
          onClick={handleAnalyze}
          disabled={!draft.photoFile}
          className="w-full py-4 rounded-xl text-base font-600 flex items-center justify-center gap-2 btn-primary min-h-[56px]"
        >
          <Icon name="SparklesIcon" size={20} className="text-primary-foreground" />
          {analysisState === 'done' ? 'Ré-analyser avec l\'IA' : 'Analyser avec l\'IA'}
        </button>
      )}

      {/* Navigation */}
      <div className="flex gap-3">
        <button
          onClick={onBack}
          className="flex-1 py-3 rounded-xl text-sm font-600 border border-border text-foreground btn-ghost flex items-center justify-center gap-2 min-h-[48px]"
        >
          <Icon name="ArrowLeftIcon" size={16} />
          Précédent
        </button>
        <button
          onClick={onNext}
          disabled={!draft.aiResult}
          className={`flex-1 py-3 rounded-xl text-sm font-600 flex items-center justify-center gap-2 min-h-[48px] ${
            draft.aiResult ? 'btn-primary' : 'bg-muted text-muted-foreground cursor-not-allowed'
          }`}
        >
          Suivant
          <Icon
            name="ArrowRightIcon"
            size={16}
            className={draft.aiResult ? 'text-primary-foreground' : 'text-muted-foreground'}
          />
        </button>
      </div>
    </div>
  );
}
