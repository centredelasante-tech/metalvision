'use client';
import React, { useState } from 'react';
import Icon from '@/components/ui/AppIcon';
import StepPhotoCapture from './StepPhotoCapture';
import StepAIResult from './StepAIResult';
import StepConfirmation from './StepConfirmation';

const STEPS = [
  { id: 1, label: 'Photo', icon: 'CameraIcon' },
  { id: 2, label: 'Analyse IA', icon: 'SparklesIcon' },
  { id: 3, label: 'Transport', icon: 'TruckIcon' },
  { id: 4, label: 'Confirmation', icon: 'CheckCircleIcon' },
];

export type TransportMode = 'internal' | 'client';

export interface TransportDraft {
  mode: TransportMode;
  // Internal MetalVision transport
  driverName: string;
  truckNumber: string;
  arrivalEta: string;
  modeTransport: 'camion' | 'rail' | 'mixte';
  gpsStart: { lat: number; lng: number } | null;
  proofPhotoFile: File | null;
  proofPhotoUrl: string;
  proofDocumentFile: File | null;
  proofDocumentUrl: string;
  // Client transport
  clientTransporterName: string;
  clientTruckNumber: string;
  clientProofPhotoFile: File | null;
  clientProofPhotoUrl: string;
}

export interface LotDraft {
  photoUrl: string;
  photoFile: File | null;
  containerId: string;
  metalType: string;
  volumeEstimated: number;
  priceEstimated: number;
  confidence: number;
  notes: string;
  referenceSizeCm: number;
  metalPricePerKg: number;
  densityOverride: number | null;
  widthCm: number;
  heightCm: number;
  depthCm: number;
  weightKg: number;
  aiExplanation: string;
  transport: TransportDraft;
}

const INITIAL_TRANSPORT: TransportDraft = {
  mode: 'internal',
  driverName: '',
  truckNumber: '',
  arrivalEta: '',
  modeTransport: 'camion',
  gpsStart: null,
  proofPhotoFile: null,
  proofPhotoUrl: '',
  proofDocumentFile: null,
  proofDocumentUrl: '',
  clientTransporterName: '',
  clientTruckNumber: '',
  clientProofPhotoFile: null,
  clientProofPhotoUrl: '',
};

const INITIAL_DRAFT: LotDraft = {
  photoUrl: '',
  photoFile: null,
  containerId: 'CT-001',
  metalType: '',
  volumeEstimated: 0,
  priceEstimated: 0,
  confidence: 0,
  notes: '',
  referenceSizeCm: 10,
  metalPricePerKg: 0,
  densityOverride: null,
  widthCm: 0,
  heightCm: 0,
  depthCm: 0,
  weightKg: 0,
  aiExplanation: '',
  transport: INITIAL_TRANSPORT,
};

export default function NewLotWizard() {
  const [step, setStep] = useState(1);
  const [draft, setDraft] = useState<LotDraft>(INITIAL_DRAFT);

  const updateDraft = (updates: Partial<LotDraft>) => {
    setDraft((prev) => ({ ...prev, ...updates }));
  };

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-700 text-foreground">Nouveau lot de métaux</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Photographiez votre lot pour obtenir une estimation IA instantanée
        </p>
      </div>

      {/* Step Indicator */}
      <div className="bg-card rounded-xl border border-border p-5">
        <div className="flex items-center gap-0">
          {STEPS.map((s, idx) => (
            <React.Fragment key={`step-${s.id}`}>
              <div className="flex flex-col items-center gap-1.5 flex-1">
                <div
                  className={`w-10 h-10 rounded-full flex items-center justify-center transition-all ${
                    step > s.id
                      ? 'bg-primary text-primary-foreground'
                      : step === s.id
                      ? 'bg-primary text-primary-foreground ring-4 ring-primary/20'
                      : 'bg-muted text-muted-foreground'
                  }`}
                >
                  {step > s.id ? (
                    <Icon name="CheckIcon" size={18} />
                  ) : (
                    <Icon name={s.icon as Parameters<typeof Icon>[0]['name']} size={18} />
                  )}
                </div>
                <span className={`text-xs font-600 ${step === s.id ? 'text-primary' : 'text-muted-foreground'}`}>
                  {s.label}
                </span>
              </div>
              {idx < STEPS.length - 1 && (
                <div className={`flex-1 h-0.5 mb-5 transition-all ${step > s.id ? 'bg-primary' : 'bg-muted'}`} />
              )}
            </React.Fragment>
          ))}
        </div>
      </div>

      {/* Step Content */}
      {step === 1 && (
        <StepPhotoCapture
          draft={draft}
          updateDraft={updateDraft}
          onNext={() => setStep(2)}
        />
      )}
      {step === 2 && (
        <StepAIResult
          draft={draft}
          updateDraft={updateDraft}
          onNext={() => setStep(3)}
          onBack={() => setStep(1)}
        />
      )}
      {step === 3 && (
        <StepTransport
          draft={draft}
          updateDraft={updateDraft}
          onNext={() => setStep(4)}
          onBack={() => setStep(2)}
        />
      )}
      {step === 4 && (
        <StepConfirmation
          draft={draft}
          onBack={() => setStep(3)}
        />
      )}
    </div>
  );
}

// ── StepTransport Component ──────────────────────────────────────────────────

interface StepTransportProps {
  draft: LotDraft;
  updateDraft: (updates: Partial<LotDraft>) => void;
  onNext: () => void;
  onBack: () => void;
}

function StepTransport({ draft, updateDraft, onNext, onBack }: StepTransportProps) {
  const t = draft.transport;

  const updateTransport = (updates: Partial<TransportDraft>) => {
    updateDraft({ transport: { ...t, ...updates } });
  };

  const canProceed = t.mode === 'internal'
    ? (t.driverName.trim() !== '' && t.truckNumber.trim() !== '')
    : (t.clientTransporterName.trim() !== '');

  return (
    <div className="space-y-4">
      {/* Mode selector */}
      <div className="bg-card rounded-xl border border-border overflow-hidden">
        <div className="px-5 py-4 border-b border-border">
          <h3 className="text-sm font-600 text-foreground">Mode de transport</h3>
          <p className="text-xs text-muted-foreground mt-0.5">Choisissez comment votre lot sera transporté</p>
        </div>
        <div className="p-5 grid grid-cols-1 sm:grid-cols-2 gap-3">
          <button
            onClick={() => updateTransport({ mode: 'internal' })}
            className={`flex items-start gap-3 p-4 rounded-xl border-2 text-left transition-all ${
              t.mode === 'internal' ?'border-primary bg-secondary' :'border-border bg-muted hover:border-primary/40'
            }`}
          >
            <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 ${t.mode === 'internal' ? 'bg-primary' : 'bg-muted-foreground/20'}`}>
              <Icon name="TruckIcon" size={20} className={t.mode === 'internal' ? 'text-primary-foreground' : 'text-muted-foreground'} />
            </div>
            <div>
              <p className={`text-sm font-700 ${t.mode === 'internal' ? 'text-primary' : 'text-foreground'}`}>
                Transport interne MetalVision
              </p>
              <p className="text-xs text-muted-foreground mt-0.5">Notre flotte prend en charge votre lot</p>
              <span className="inline-block mt-1.5 text-[10px] font-600 text-green-700 bg-green-50 border border-green-200 px-2 py-0.5 rounded-full">
                Frais de transport : 0 $
              </span>
            </div>
          </button>

          <button
            onClick={() => updateTransport({ mode: 'client' })}
            className={`flex items-start gap-3 p-4 rounded-xl border-2 text-left transition-all ${
              t.mode === 'client' ?'border-primary bg-secondary' :'border-border bg-muted hover:border-primary/40'
            }`}
          >
            <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 ${t.mode === 'client' ? 'bg-primary' : 'bg-muted-foreground/20'}`}>
              <Icon name="UserIcon" size={20} className={t.mode === 'client' ? 'text-primary-foreground' : 'text-muted-foreground'} />
            </div>
            <div>
              <p className={`text-sm font-700 ${t.mode === 'client' ? 'text-primary' : 'text-foreground'}`}>
                Transport du client
              </p>
              <p className="text-xs text-muted-foreground mt-0.5">Vous gérez votre propre transport</p>
            </div>
          </button>
        </div>
      </div>

      {/* Internal transport form */}
      {t.mode === 'internal' && (
        <div className="bg-card rounded-xl border border-border overflow-hidden">
          <div className="px-5 py-4 border-b border-border flex items-center gap-2">
            <Icon name="TruckIcon" size={16} className="text-primary" />
            <h3 className="text-sm font-600 text-foreground">Détails du transport interne</h3>
          </div>
          <div className="p-5 space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-600 text-foreground mb-1.5">
                  Nom du chauffeur <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={t.driverName}
                  onChange={(e) => updateTransport({ driverName: e.target.value })}
                  placeholder="Jean Tremblay"
                  className="w-full px-3 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
                />
              </div>
              <div>
                <label className="block text-xs font-600 text-foreground mb-1.5">
                  Numéro de camion <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={t.truckNumber}
                  onChange={(e) => updateTransport({ truckNumber: e.target.value })}
                  placeholder="QC-4821-A"
                  className="w-full px-3 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
                />
              </div>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-600 text-foreground mb-1.5">ETA d&apos;arrivée</label>
                <input
                  type="datetime-local"
                  value={t.arrivalEta}
                  onChange={(e) => updateTransport({ arrivalEta: e.target.value })}
                  className="w-full px-3 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
                />
              </div>
              <div>
                <label className="block text-xs font-600 text-foreground mb-1.5">Mode de transport</label>
                <select
                  value={t.modeTransport}
                  onChange={(e) => updateTransport({ modeTransport: e.target.value as 'camion' | 'rail' | 'mixte' })}
                  className="w-full px-3 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
                >
                  <option value="camion">Camion</option>
                  <option value="rail">Rail</option>
                  <option value="mixte">Mixte</option>
                </select>
              </div>
            </div>

            <div>
              <label className="block text-xs font-600 text-foreground mb-1.5">Photo de preuve</label>
              <label className="flex items-center gap-3 p-3 border border-dashed border-border rounded-lg cursor-pointer hover:border-primary/40 transition-colors">
                <Icon name="CameraIcon" size={18} className="text-muted-foreground flex-shrink-0" />
                <span className="text-sm text-muted-foreground">
                  {t.proofPhotoFile ? t.proofPhotoFile.name : 'Ajouter une photo de preuve'}
                </span>
                <input
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={(e) => {
                    const file = e.target.files?.[0] ?? null;
                    updateTransport({
                      proofPhotoFile: file,
                      proofPhotoUrl: file ? URL.createObjectURL(file) : '',
                    });
                  }}
                />
              </label>
            </div>

            <div>
              <label className="block text-xs font-600 text-foreground mb-1.5">Document de preuve (PDF, image)</label>
              <label className="flex items-center gap-3 p-3 border border-dashed border-border rounded-lg cursor-pointer hover:border-primary/40 transition-colors">
                <Icon name="DocumentTextIcon" size={18} className="text-muted-foreground flex-shrink-0" />
                <span className="text-sm text-muted-foreground">
                  {t.proofDocumentFile ? t.proofDocumentFile.name : 'Ajouter un document de preuve'}
                </span>
                <input
                  type="file"
                  accept=".pdf,image/*"
                  className="hidden"
                  onChange={(e) => {
                    const file = e.target.files?.[0] ?? null;
                    updateTransport({
                      proofDocumentFile: file,
                      proofDocumentUrl: file ? URL.createObjectURL(file) : '',
                    });
                  }}
                />
              </label>
            </div>
          </div>
        </div>
      )}

      {/* Client transport form */}
      {t.mode === 'client' && (
        <div className="bg-card rounded-xl border border-border overflow-hidden">
          <div className="px-5 py-4 border-b border-border flex items-center gap-2">
            <Icon name="UserIcon" size={16} className="text-primary" />
            <h3 className="text-sm font-600 text-foreground">Détails du transport client</h3>
          </div>
          <div className="p-5 space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label className="block text-xs font-600 text-foreground mb-1.5">
                  Nom du transporteur <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  value={t.clientTransporterName}
                  onChange={(e) => updateTransport({ clientTransporterName: e.target.value })}
                  placeholder="Nom de votre transporteur"
                  className="w-full px-3 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
                />
              </div>
              <div>
                <label className="block text-xs font-600 text-foreground mb-1.5">Numéro de camion</label>
                <input
                  type="text"
                  value={t.clientTruckNumber}
                  onChange={(e) => updateTransport({ clientTruckNumber: e.target.value })}
                  placeholder="Plaque ou numéro"
                  className="w-full px-3 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
                />
              </div>
            </div>

            <div>
              <label className="block text-xs font-600 text-foreground mb-1.5">Photo de preuve</label>
              <label className="flex items-center gap-3 p-3 border border-dashed border-border rounded-lg cursor-pointer hover:border-primary/40 transition-colors">
                <Icon name="CameraIcon" size={18} className="text-muted-foreground flex-shrink-0" />
                <span className="text-sm text-muted-foreground">
                  {t.clientProofPhotoFile ? t.clientProofPhotoFile.name : 'Ajouter une photo de preuve'}
                </span>
                <input
                  type="file"
                  accept="image/*"
                  className="hidden"
                  onChange={(e) => {
                    const file = e.target.files?.[0] ?? null;
                    updateTransport({
                      clientProofPhotoFile: file,
                      clientProofPhotoUrl: file ? URL.createObjectURL(file) : '',
                    });
                  }}
                />
              </label>
            </div>
          </div>
        </div>
      )}

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
          disabled={!canProceed}
          className="flex-1 btn-primary py-3 rounded-xl text-sm font-600 flex items-center justify-center gap-2 disabled:opacity-50"
        >
          Continuer
          <Icon name="ArrowRightIcon" size={16} className="text-primary-foreground" />
        </button>
      </div>
    </div>
  );
}