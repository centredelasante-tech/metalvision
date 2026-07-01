'use client';
import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { LotDraft } from './NewLotWizard';

const METAL_TYPES = [
  'aluminium',
  'cuivre',
  'laiton',
  'acier',
  'inox',
  'fonte',
  'mélange',
];

interface Props {
  draft: LotDraft;
  updateDraft: (u: Partial<LotDraft>) => void;
  onBack: () => void;
}

type SubmitState = 'idle' | 'loading' | 'success' | 'error';

export default function StepConfirmSubmit({ draft, updateDraft, onBack }: Props) {
  const { user } = useAuth();
  const router = useRouter();
  const [submitState, setSubmitState] = useState<SubmitState>('idle');
  const [submitError, setSubmitError] = useState('');

  const ai = draft.aiResult;

  const handleSubmit = async () => {
    if (!draft.container || !user) return;
    setSubmitState('loading');
    setSubmitError('');

    try {
      const supabase = createClient();

      // 1. Get company_id from company_members
      const { data: memberData, error: memberError } = await supabase
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1)
        .single();

      if (memberError || !memberData) {
        throw new Error('Impossible de récupérer votre entreprise. Vérifiez votre accès.');
      }

      const companyId = memberData.company_id;

      // 2. Direct Supabase insert into raw_measurements
      const { error: insertError } = await supabase.from('raw_measurements').insert({
        company_id: companyId,
        container_id: draft.container.id,
        client_id: user.id,
        metal_type_predicted: draft.metalType,
        confidence: ai?.confidence ?? 0,
        width_cm: ai?.width_cm ?? 0,
        height_cm: ai?.height_cm ?? 0,
        depth_cm: ai?.depth_cm ?? 0,
        volume_estimated_m3: draft.volumeM3,
        weight_kg: draft.weightKg,
        compaction_visual: ai?.compaction_visual ?? null,
        purity_visual: ai?.purity_visual ?? null,
        object_type: ai?.object_type ?? null,
        raw_analysis_json: ai ?? null,
        reference_size_cm: draft.referenceSizeCm,
        notes: draft.notes || null,
        status: 'submitted',
      });

      if (insertError) {
        throw new Error(insertError.message || 'Erreur lors de l\'enregistrement du lot.');
      }

      setSubmitState('success');
      // Redirect after short delay
      setTimeout(() => router.push('/'), 1800);
    } catch (err: unknown) {
      setSubmitError(err instanceof Error ? err.message : 'Erreur inconnue');
      setSubmitState('error');
    }
  };

  if (submitState === 'success') {
    return (
      <div className="bg-card rounded-xl border border-primary/20 p-8 text-center">
        <div className="w-20 h-20 bg-secondary rounded-full flex items-center justify-center mx-auto mb-5">
          <Icon name="CheckCircleIcon" size={40} className="text-primary" />
        </div>
        <h3 className="text-xl font-700 text-foreground">Lot soumis avec succès !</h3>
        <p className="text-sm text-muted-foreground mt-2 mb-6">
          Votre lot a été enregistré. Redirection vers le tableau de bord…
        </p>
        <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin mx-auto" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Editable AI results */}
      <div className="bg-card rounded-xl border border-border overflow-hidden">
        <div className="flex items-center gap-2 px-5 py-4 border-b border-border bg-secondary">
          <Icon name="SparklesIcon" size={16} className="text-primary" />
          <h3 className="text-sm font-600 text-primary">Résultats de l'analyse IA</h3>
          {ai && (
            <span className="ml-auto text-xs font-600 text-primary bg-primary/10 px-2.5 py-1 rounded-full">
              Confiance {Math.round(ai.confidence * 100)}%
            </span>
          )}
        </div>

        <div className="p-5 space-y-4">
          {/* Metal type dropdown */}
          <div>
            <label className="block text-xs font-600 text-foreground mb-1.5">
              Type de métal <span className="text-red-500">*</span>
            </label>
            <select
              value={draft.metalType}
              onChange={(e) => updateDraft({ metalType: e.target.value })}
              className="w-full px-3 py-3 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
            >
              <option value="">Sélectionner…</option>
              {METAL_TYPES.map((m) => (
                <option key={`metal-${m}`} value={m}>
                  {m.charAt(0).toUpperCase() + m.slice(1)}
                </option>
              ))}
            </select>
          </div>

          {/* Volume + Weight */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-600 text-foreground mb-1.5">
                Volume estimé (m³)
              </label>
              <input
                type="number"
                step="0.0001"
                min="0"
                value={draft.volumeM3}
                onChange={(e) => updateDraft({ volumeM3: parseFloat(e.target.value) || 0 })}
                className="w-full px-3 py-3 rounded-lg border border-border bg-input text-foreground text-sm tabular-nums focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
              />
            </div>
            <div>
              <label className="block text-xs font-600 text-foreground mb-1.5">
                Poids estimé (kg)
              </label>
              <input
                type="number"
                step="0.1"
                min="0"
                value={draft.weightKg}
                onChange={(e) => updateDraft({ weightKg: parseFloat(e.target.value) || 0 })}
                className="w-full px-3 py-3 rounded-lg border border-border bg-input text-foreground text-sm tabular-nums focus:outline-none focus:ring-2 focus:ring-ring min-h-[48px]"
              />
            </div>
          </div>

          {/* Confidence (read-only) */}
          {ai && (
            <div>
              <label className="block text-xs font-600 text-muted-foreground mb-1.5 uppercase tracking-wide">
                Confiance IA
              </label>
              <div className="px-3 py-3 rounded-lg border border-border bg-muted text-foreground text-sm tabular-nums min-h-[48px] flex items-center">
                {Math.round(ai.confidence * 100)}%
              </div>
            </div>
          )}

          {/* Explanation (read-only) */}
          {ai?.explanation && (
            <div>
              <label className="block text-xs font-600 text-muted-foreground mb-1.5 uppercase tracking-wide">
                Explication IA
              </label>
              <div className="px-3 py-3 rounded-lg border border-border bg-muted text-foreground text-xs leading-relaxed min-h-[64px]">
                {ai.explanation}
              </div>
            </div>
          )}

          {/* Notes */}
          <div>
            <label className="block text-xs font-600 text-foreground mb-1.5">
              Notes libres <span className="text-muted-foreground font-400">(optionnel)</span>
            </label>
            <textarea
              value={draft.notes}
              onChange={(e) => updateDraft({ notes: e.target.value })}
              placeholder="Informations complémentaires sur le lot…"
              rows={3}
              className="w-full px-3 py-3 rounded-lg border border-border bg-input text-foreground text-sm resize-none focus:outline-none focus:ring-2 focus:ring-ring placeholder:text-muted-foreground min-h-[80px]"
            />
          </div>
        </div>
      </div>

      {/* Container summary */}
      {draft.container && (
        <div className="flex items-center gap-3 p-4 bg-muted rounded-xl">
          <Icon name="ArchiveBoxIcon" size={16} className="text-muted-foreground flex-shrink-0" />
          <div>
            <p className="text-xs text-muted-foreground">Conteneur</p>
            <p className="text-sm font-700 text-foreground">{draft.container.name}</p>
          </div>
        </div>
      )}

      {/* Error */}
      {submitState === 'error' && submitError && (
        <div className="flex items-start gap-2 p-4 bg-red-50 border border-red-200 rounded-xl">
          <Icon name="ExclamationCircleIcon" size={16} className="text-red-500 flex-shrink-0 mt-0.5" />
          <p className="text-sm text-red-700">{submitError}</p>
        </div>
      )}

      {/* Actions */}
      <div className="flex gap-3">
        <button
          onClick={onBack}
          disabled={submitState === 'loading'}
          className="flex-1 py-3 rounded-xl text-sm font-600 border border-border text-foreground btn-ghost flex items-center justify-center gap-2 min-h-[48px] disabled:opacity-50"
        >
          <Icon name="ArrowLeftIcon" size={16} />
          Précédent
        </button>
        <button
          onClick={handleSubmit}
          disabled={submitState === 'loading' || !draft.metalType || !draft.container}
          className={`flex-1 py-3 rounded-xl text-sm font-600 flex items-center justify-center gap-2 min-h-[48px] ${
            submitState === 'loading' || !draft.metalType || !draft.container ?'bg-muted text-muted-foreground cursor-not-allowed' :'btn-primary'
          }`}
        >
          {submitState === 'loading' ? (
            <>
              <div className="w-4 h-4 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" />
              Soumission…
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
