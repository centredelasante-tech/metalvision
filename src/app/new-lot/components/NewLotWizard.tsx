'use client';
import React, { useState } from 'react';
import Icon from '@/components/ui/AppIcon';
import StepContainer from './StepContainer';
import StepPhotoAnalysis from './StepPhotoAnalysis';
import StepConfirmSubmit from './StepConfirmSubmit';

const STEPS = [
  { id: 1, label: 'Conteneur', icon: 'ArchiveBoxIcon' },
  { id: 2, label: 'Photo & IA', icon: 'CameraIcon' },
  { id: 3, label: 'Confirmation', icon: 'CheckCircleIcon' },
];

export interface SelectedContainer {
  id: string;
  name: string;
  location: string | null;
}

export interface AIAnalysisResult {
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
  object_type?: string | null;
  explanation: string;
}

export interface LotDraft {
  container: SelectedContainer | null;
  photoFile: File | null;
  photoUrl: string;
  referenceSizeCm: number;
  aiResult: AIAnalysisResult | null;
  // Step 3 editable fields
  metalType: string;
  volumeM3: number;
  weightKg: number;
  notes: string;
}

const INITIAL_DRAFT: LotDraft = {
  container: null,
  photoFile: null,
  photoUrl: '',
  referenceSizeCm: 30,
  aiResult: null,
  metalType: '',
  volumeM3: 0,
  weightKg: 0,
  notes: '',
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
          Sélectionnez un conteneur, photographiez le lot et confirmez l'analyse IA
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
                <span
                  className={`text-xs font-600 ${
                    step === s.id ? 'text-primary' : 'text-muted-foreground'
                  }`}
                >
                  {s.label}
                </span>
              </div>
              {idx < STEPS.length - 1 && (
                <div
                  className={`flex-1 h-0.5 mb-5 transition-all ${
                    step > s.id ? 'bg-primary' : 'bg-muted'
                  }`}
                />
              )}
            </React.Fragment>
          ))}
        </div>
      </div>

      {/* Step Content */}
      {step === 1 && (
        <StepContainer
          draft={draft}
          updateDraft={updateDraft}
          onNext={() => setStep(2)}
        />
      )}
      {step === 2 && (
        <StepPhotoAnalysis
          draft={draft}
          updateDraft={updateDraft}
          onNext={() => setStep(3)}
          onBack={() => setStep(1)}
        />
      )}
      {step === 3 && (
        <StepConfirmSubmit
          draft={draft}
          updateDraft={updateDraft}
          onBack={() => setStep(2)}
        />
      )}
    </div>
  );
}