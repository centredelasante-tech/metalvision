'use client';
import React, { useState } from 'react';
import Icon from '@/components/ui/AppIcon';
import StepPhotoCapture from './StepPhotoCapture';
import StepAIResult from './StepAIResult';
import StepConfirmation from './StepConfirmation';

const STEPS = [
  { id: 1, label: 'Photo', icon: 'CameraIcon' },
  { id: 2, label: 'Analyse IA', icon: 'SparklesIcon' },
  { id: 3, label: 'Confirmation', icon: 'CheckCircleIcon' },
];

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
  // Extended AI result fields
  widthCm: number;
  heightCm: number;
  depthCm: number;
  weightKg: number;
  aiExplanation: string;
}

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
                <div className={`flex-1 h-0.5 mb-5 transition-all ${step > s.id + 0 ? 'bg-primary' : 'bg-muted'}`} />
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
        <StepConfirmation
          draft={draft}
          onBack={() => setStep(2)}
        />
      )}
    </div>
  );
}