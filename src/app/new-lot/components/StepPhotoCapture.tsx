'use client';
import React, { useState, useRef, useCallback, useEffect } from 'react';
import Icon from '@/components/ui/AppIcon';
import { LotDraft } from './NewLotWizard';

const CONTAINERS = ['CT-001', 'CT-002', 'CT-003', 'CT-004'];

const METAL_PRICES: Record<string, number> = {
  fer: 0.27,
  acier: 0.35,
  aluminium: 2.72,
  cuivre: 10.90,
  laiton: 7.05,
  inox: 1.76,
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
          if (blob) {
            resolve(new File([blob], file.name, { type: 'image/jpeg' }));
          } else {
            resolve(file);
          }
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
}

export default function StepPhotoCapture({ draft, updateDraft, onNext }: Props) {
  const [captureMode, setCaptureMode] = useState<'idle' | 'preview'>('idle');
  const [selectedFile, setSelectedFile] = useState<string>('');
  const [compressing, setCompressing] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const handleFileChange = useCallback(async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setCompressing(true);
    try {
      const compressed = await compressImage(file);
      const url = URL.createObjectURL(compressed);
      setSelectedFile(url);
      updateDraft({ photoUrl: url, photoFile: compressed });
      setCaptureMode('preview');
    } finally {
      setCompressing(false);
    }
  }, [updateDraft]);

  const handleSimulateCapture = () => {
    if (fileRef.current) {
      fileRef.current.accept = 'image/*';
      fileRef.current.capture = 'environment';
      fileRef.current.click();
    }
  };

  const handleRetake = () => {
    setCaptureMode('idle');
    setSelectedFile('');
    updateDraft({ photoUrl: '', photoFile: null });
  };

  const canProceed = draft.photoUrl && draft.containerId && draft.metalPricePerKg > 0;

  return (
    <div className="space-y-4">
      {/* Container selector */}
      <div className="bg-card rounded-xl border border-border p-4 md:p-5">
        <label className="block text-base font-600 text-foreground mb-1">
          Conteneur associé <span className="text-red-500">*</span>
        </label>
        <p className="text-sm text-muted-foreground mb-3">
          Sélectionnez le conteneur d'où provient ce lot de métaux
        </p>
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
          {CONTAINERS.map((c) => (
            <button
              key={`container-select-${c}`}
              onClick={() => updateDraft({ containerId: c })}
              className={`py-3 rounded-lg text-sm font-600 border transition-all min-h-[48px] ${
                draft.containerId === c
                  ? 'bg-primary text-primary-foreground border-primary'
                  : 'bg-muted text-foreground border-border btn-ghost'
              }`}
            >
              {c}
            </button>
          ))}
        </div>
      </div>

      {/* AI Parameters */}
      <div className="bg-card rounded-xl border border-border p-4 md:p-5">
        <h3 className="text-base font-600 text-foreground mb-1">Paramètres d'analyse IA</h3>
        <p className="text-sm text-muted-foreground mb-4">
          Ces valeurs permettent à l'IA de calculer le volume et la valeur estimée du lot.
        </p>
        <div className="flex flex-col space-y-4">
          <div>
            <label className="block text-sm font-600 text-foreground mb-1.5">
              Taille de la référence visible (cm) <span className="text-red-500">*</span>
            </label>
            <p className="text-xs text-muted-foreground mb-2">Ex : QR code 10 cm, règle, objet connu</p>
            <input
              type="number"
              min="1"
              step="0.5"
              value={draft.referenceSizeCm}
              onChange={(e) => updateDraft({ referenceSizeCm: parseFloat(e.target.value) || 10 })}
              className="w-full px-3 py-3 rounded-lg border border-border bg-input text-foreground text-base tabular-nums focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
            />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1.5">
              Prix du métal ($/kg CAD) <span className="text-red-500">*</span>
            </label>
            <p className="text-xs text-muted-foreground mb-2">Sélectionnez un métal ou entrez manuellement</p>
            <div className="flex flex-col sm:flex-row gap-2">
              <select
                onChange={(e) => {
                  const price = METAL_PRICES[e.target.value];
                  if (price) updateDraft({ metalPricePerKg: price });
                }}
                className="w-full px-3 py-3 rounded-lg border border-border bg-input text-foreground text-base focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
              >
                <option value="">Choisir un métal...</option>
                {Object.entries(METAL_PRICES).map(([metal, price]) => (
                  <option key={`price-${metal}`} value={metal}>
                    {metal.charAt(0).toUpperCase() + metal.slice(1)} — {price.toFixed(2)} $CA
                  </option>
                ))}
              </select>
              <input
                type="number"
                min="0"
                step="0.01"
                value={draft.metalPricePerKg || ''}
                onChange={(e) => updateDraft({ metalPricePerKg: parseFloat(e.target.value) || 0 })}
                placeholder="$/kg"
                className="w-full sm:w-28 px-3 py-3 rounded-lg border border-border bg-input text-foreground text-base tabular-nums focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
              />
            </div>
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1.5">
              Densité manuelle (kg/m³) <span className="text-muted-foreground font-400">(optionnel)</span>
            </label>
            <p className="text-xs text-muted-foreground mb-2">Laissez vide pour utiliser la densité standard</p>
            <input
              type="number"
              min="0"
              step="10"
              value={draft.densityOverride ?? ''}
              onChange={(e) => {
                const val = e.target.value;
                updateDraft({ densityOverride: val ? parseFloat(val) : null });
              }}
              placeholder="Ex: 8960 pour cuivre"
              className="w-full px-3 py-3 rounded-lg border border-border bg-input text-foreground text-base tabular-nums focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
            />
          </div>
        </div>
      </div>

      {/* Photo capture */}
      <div className="bg-card rounded-xl border border-border p-4 md:p-5">
        <label className="block text-base font-600 text-foreground mb-1">
          Photo du lot <span className="text-red-500">*</span>
        </label>
        <p className="text-sm text-muted-foreground mb-4">
          Prenez une photo claire du lot avec une référence de taille visible. L'IA analysera le type de métal et le volume estimé.
        </p>

        {compressing && (
          <div className="flex items-center justify-center gap-3 py-8">
            <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
            <p className="text-sm text-muted-foreground font-500">Compression de l'image...</p>
          </div>
        )}

        {!compressing && captureMode === 'idle' && (
          <div className="flex flex-col gap-3">
            <button
              onClick={handleSimulateCapture}
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
              onClick={() => {
                if (fileRef.current) {
                  fileRef.current.removeAttribute('capture');
                  fileRef.current.accept = 'image/*';
                  fileRef.current.click();
                }
              }}
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
            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              className="hidden"
              onChange={handleFileChange}
            />
          </div>
        )}

        {!compressing && captureMode === 'preview' && (
          <div className="space-y-4">
            {/* Fullscreen-style preview */}
            <div className="relative rounded-xl overflow-hidden bg-gray-100 w-full" style={{ aspectRatio: '4/3' }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={selectedFile}
                alt="Photo du lot de métaux capturée"
                className="w-full h-full object-cover"
              />
              <div className="absolute bottom-3 left-3 bg-primary/90 rounded-lg px-3 py-1">
                <p className="text-primary-foreground text-xs font-600">Photo prête pour analyse IA</p>
              </div>
            </div>
            {/* Retake button - prominent */}
            <button
              onClick={handleRetake}
              className="w-full flex items-center justify-center gap-2 py-3 rounded-xl border-2 border-border text-foreground font-600 text-sm btn-ghost min-h-[48px]"
            >
              <Icon name="ArrowPathIcon" size={18} />
              Reprendre la photo
            </button>
            <div className="flex items-center gap-2 p-3 bg-secondary rounded-lg">
              <Icon name="CheckCircleIcon" size={18} className="text-primary flex-shrink-0" />
              <p className="text-sm text-primary font-500">Photo capturée et compressée avec succès</p>
            </div>
          </div>
        )}
      </div>

      {/* Notes */}
      <div className="bg-card rounded-xl border border-border p-4 md:p-5">
        <label className="block text-base font-600 text-foreground mb-1">
          Notes (optionnel)
        </label>
        <p className="text-sm text-muted-foreground mb-3">
          Informations complémentaires sur le lot (origine, traitement, état)
        </p>
        <textarea
          value={draft.notes}
          onChange={(e) => updateDraft({ notes: e.target.value })}
          placeholder="Ex: Câbles électriques provenant de la démolition du bâtiment B..."
          rows={3}
          className="w-full px-4 py-3 rounded-lg border border-border bg-input text-foreground text-base resize-none focus:outline-none focus:ring-2 focus:ring-ring placeholder:text-muted-foreground min-h-[96px]"
        />
      </div>

      {/* Next */}
      <button
        onClick={onNext}
        disabled={!canProceed}
        className={`w-full py-4 rounded-xl text-base font-600 flex items-center justify-center gap-2 transition-all min-h-[56px] ${
          canProceed
            ? 'btn-primary' : 'bg-muted text-muted-foreground cursor-not-allowed'
        }`}
      >
        <Icon name="SparklesIcon" size={20} className={canProceed ? 'text-primary-foreground' : 'text-muted-foreground'} />
        Analyser avec l'IA
      </button>
      {!canProceed && (draft.photoUrl || draft.metalPricePerKg > 0) && (
        <p className="text-sm text-muted-foreground text-center -mt-2">
          {!draft.photoUrl ? 'Ajoutez une photo' : !draft.metalPricePerKg ? 'Entrez le prix du métal ($/kg)' : ''}
        </p>
      )}
    </div>
  );
}