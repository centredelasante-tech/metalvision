'use client';
import React, { useState } from 'react';
import Link from 'next/link';
import Icon from '@/components/ui/AppIcon';
import MetalBadge from '@/components/ui/MetalBadge';
import StatusBadge from '@/components/ui/StatusBadge';
import { LotDraft } from './NewLotWizard';

interface Props {
  draft: LotDraft;
  onBack: () => void;
}

type SubmitState = 'idle' | 'loading' | 'success' | 'error';

export default function StepConfirmation({ draft, onBack }: Props) {
  const [submitState, setSubmitState] = useState<SubmitState>('idle');
  const [lotId, setLotId] = useState('');

  const handleSubmit = () => {
    setSubmitState('loading');
    // BACKEND INTEGRATION: POST to /api/lots with draft data
    setTimeout(() => {
      setLotId('LOT-0848');
      setSubmitState('success');
    }, 1800);
  };

  if (submitState === 'success') {
    return (
      <div className="bg-card rounded-xl border border-primary/20 p-8 text-center fade-in-up">
        <div className="w-20 h-20 bg-secondary rounded-full flex items-center justify-center mx-auto mb-5">
          <Icon name="CheckCircleIcon" size={40} className="text-primary" />
        </div>
        <h3 className="text-xl font-700 text-foreground">Lot soumis avec succès !</h3>
        <p className="text-sm text-muted-foreground mt-2 mb-2">
          Votre lot a été enregistré et sera traité par notre équipe sous 48h.
        </p>
        <div className="inline-flex items-center gap-2 bg-secondary px-4 py-2 rounded-lg mb-6">
          <Icon name="DocumentTextIcon" size={16} className="text-primary" />
          <span className="text-sm font-700 text-primary tabular-nums">#{lotId}</span>
        </div>

        <div className="bg-muted rounded-xl p-4 text-left mb-6 space-y-2">
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Conteneur</span>
            <span className="font-600">{draft.containerId}</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Métal détecté</span>
            <MetalBadge metal={draft.metalType} />
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Prix estimé</span>
            <span className="font-700 text-primary tabular-nums">{draft.priceEstimated.toFixed(2)} $CA</span>
          </div>
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">Statut</span>
            <StatusBadge status="submitted" size="sm" />
          </div>
        </div>

        <div className="flex gap-3">
          <Link href="/" className="flex-1 btn-primary py-3 rounded-xl text-sm font-600 flex items-center justify-center gap-2">
            <Icon name="HomeIcon" size={16} className="text-primary-foreground" />
            Tableau de bord
          </Link>
          <Link href="/new-lot" className="flex-1 py-3 rounded-xl text-sm font-600 border border-border text-foreground btn-ghost flex items-center justify-center gap-2">
            <Icon name="PlusIcon" size={16} />
            Nouveau lot
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Summary */}
      <div className="bg-card rounded-xl border border-border overflow-hidden">
        <div className="px-5 py-4 border-b border-border">
          <h3 className="text-sm font-600 text-foreground">Récapitulatif du lot</h3>
          <p className="text-xs text-muted-foreground mt-0.5">Vérifiez les informations avant de soumettre</p>
        </div>

        <div className="p-5 space-y-4">
          {/* Photo preview */}
          {draft.photoUrl && (
            <div className="relative rounded-xl overflow-hidden bg-gray-100 h-40">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={draft.photoUrl}
                alt="Photo du lot de métaux pour confirmation"
                className="w-full h-full object-cover"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-black/40 to-transparent" />
              <div className="absolute bottom-3 left-3">
                <span className="text-white text-xs font-600 bg-black/50 px-2 py-1 rounded">
                  Photo du lot
                </span>
              </div>
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <div className="p-3 bg-muted rounded-lg">
              <p className="text-[11px] font-600 uppercase tracking-wide text-muted-foreground mb-1">Conteneur</p>
              <p className="text-sm font-700 text-foreground">{draft.containerId}</p>
            </div>
            <div className="p-3 bg-muted rounded-lg">
              <p className="text-[11px] font-600 uppercase tracking-wide text-muted-foreground mb-1">Type de métal</p>
              <MetalBadge metal={draft.metalType} />
            </div>
            <div className="p-3 bg-muted rounded-lg">
              <p className="text-[11px] font-600 uppercase tracking-wide text-muted-foreground mb-1">Volume estimé</p>
              <p className="text-sm font-700 tabular-nums text-foreground">{draft.volumeEstimated.toFixed(2)} m³</p>
            </div>
            <div className="p-3 bg-secondary rounded-lg">
              <p className="text-[11px] font-600 uppercase tracking-wide text-muted-foreground mb-1">Prix estimé</p>
              <p className="text-sm font-700 tabular-nums text-primary">{draft.priceEstimated.toFixed(2)} $CA</p>
            </div>
            <div className="p-3 bg-muted rounded-lg">
              <p className="text-[11px] font-600 uppercase tracking-wide text-muted-foreground mb-1">Confiance IA</p>
              <p className="text-sm font-700 tabular-nums text-foreground">{draft.confidence}%</p>
            </div>
            <div className="p-3 bg-muted rounded-lg">
              <p className="text-[11px] font-600 uppercase tracking-wide text-muted-foreground mb-1">Statut initial</p>
              <StatusBadge status="submitted" size="sm" />
            </div>
          </div>

          {draft.notes && (
            <div className="p-3 bg-muted rounded-lg">
              <p className="text-[11px] font-600 uppercase tracking-wide text-muted-foreground mb-1">Notes</p>
              <p className="text-sm text-foreground">{draft.notes}</p>
            </div>
          )}
        </div>
      </div>

      {/* Info */}
      <div className="flex items-start gap-3 p-4 bg-secondary rounded-xl border border-primary/20">
        <Icon name="InformationCircleIcon" size={18} className="text-primary flex-shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-600 text-primary">Prochaines étapes</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Notre équipe traitera votre lot sous 48h. Vous recevrez une notification lorsque le prix final sera confirmé et la facture générée.
          </p>
        </div>
      </div>

      {/* Actions */}
      <div className="flex gap-3">
        <button
          onClick={onBack}
          disabled={submitState === 'loading'}
          className="flex-1 py-3 rounded-xl text-sm font-600 border border-border text-foreground btn-ghost flex items-center justify-center gap-2 disabled:opacity-50"
        >
          <Icon name="ArrowLeftIcon" size={16} />
          Modifier
        </button>
        <button
          onClick={handleSubmit}
          disabled={submitState === 'loading'}
          className="flex-1 btn-primary py-3 rounded-xl text-sm font-600 flex items-center justify-center gap-2 disabled:opacity-70"
        >
          {submitState === 'loading' ? (
            <>
              <Icon name="ArrowPathIcon" size={16} className="text-primary-foreground animate-spin" />
              Soumission...
            </>
          ) : (
            <>
              <Icon name="PaperAirplaneIcon" size={16} className="text-primary-foreground" />
              Soumettre le lot
            </>
          )}
        </button>
      </div>
    </div>
  );
}