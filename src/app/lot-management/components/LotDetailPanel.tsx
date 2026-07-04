'use client';
import React, { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import StatusBadge from '@/components/ui/StatusBadge';
import MetalBadge from '@/components/ui/MetalBadge';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';

const METAL_PRICES: Record<string, number> = {
  fer: 0.27,
  acier: 0.35,
  aluminium: 2.72,
  cuivre: 10.90,
  laiton: 7.05,
  inox: 1.76
};

type LotStatus = 'submitted' | 'processed' | 'invoiced';

interface LotData {
  id: string;
  lotNumber: string;
  client: string;
  container: string;
  metal: string;
  volumeEstimated: number;
  priceEstimated: number;
  confidence: number;
  status: LotStatus;
  submittedAt: string;
  notes: string;
  photoUrl: string | null;
}

interface WeightForm {
  weightReal: number;
  metalType: string;
  notes: string;
}

type SaveState = 'idle' | 'saving' | 'saved';
type InvoiceState = 'idle' | 'generating' | 'done';

interface Props {
  selectedLotId?: string;
}

export default function LotDetailPanel({ selectedLotId }: Props) {
  const [lotData, setLotData] = useState<LotData | null>(null);
  const [loading, setLoading] = useState(false);
  const [weightSaveState, setWeightSaveState] = useState<SaveState>('idle');
  const [invoiceState, setInvoiceState] = useState<InvoiceState>('idle');
  const [priceFinal, setPriceFinal] = useState<number | null>(null);
  const [activeTab, setActiveTab] = useState<'detail' | 'timeline'>('detail');

  const {
    register,
    handleSubmit,
    watch,
    reset,
    formState: { errors }
  } = useForm<WeightForm>();

  useEffect(() => {
    if (!selectedLotId) {
      setLotData(null);
      return;
    }

    const supabase = createClient();
    const fetchLot = async () => {
      setLoading(true);
      const { data, error } = await supabase
        .from('raw_measurements')
        .select('id, metal_type_predicted, official_metal_type, volume_estimated_m3, price_paid, confidence, status, created_at, notes, image_url, container_id, company_id, companies(name), containers(name)')
        .eq('id', selectedLotId)
        .single();

      if (error || !data) {
        console.error('Error fetching lot:', error?.message);
        setLoading(false);
        return;
      }

      const shortId = data.id.replace(/-/g, '').substring(0, 6).toUpperCase();
      const validStatuses: LotStatus[] = ['submitted', 'processed', 'invoiced'];
      const rawStatus = data.status as string;
      const status: LotStatus = validStatuses.includes(rawStatus as LotStatus)
        ? (rawStatus as LotStatus)
        : 'submitted';

      const dateObj = data.created_at ? new Date(data.created_at) : null;
      const submittedAt = dateObj
        ? `${String(dateObj.getDate()).padStart(2, '0')}/${String(dateObj.getMonth() + 1).padStart(2, '0')}/${dateObj.getFullYear()} ${String(dateObj.getHours()).padStart(2, '0')}:${String(dateObj.getMinutes()).padStart(2, '0')}`
        : '—';

      const lot: LotData = {
        id: data.id,
        lotNumber: `LOT-${shortId}`,
        client: (data as any).companies?.name ?? '—',
        container: (data as any).containers?.name ?? '—',
        metal: data.official_metal_type ?? data.metal_type_predicted ?? 'inconnu',
        volumeEstimated: Number(data.volume_estimated_m3 ?? 0),
        priceEstimated: Number(data.price_paid ?? 0),
        confidence: Number(data.confidence ?? 0),
        status,
        submittedAt,
        notes: data.notes ?? '',
        photoUrl: data.image_url ?? null,
      };

      setLotData(lot);
      reset({ metalType: lot.metal, notes: '' });
      setPriceFinal(null);
      setWeightSaveState('idle');
      setInvoiceState('idle');
      setLoading(false);
    };

    fetchLot();
  }, [selectedLotId, reset]);

  const watchedWeight = watch('weightReal');
  const watchedMetal = watch('metalType');

  const computedPrice =
    watchedWeight && watchedMetal
      ? Math.round(watchedWeight * (METAL_PRICES[watchedMetal] ?? 0.27) * 100) / 100
      : null;

  const onSave = async (data: WeightForm) => {
    if (!lotData) return;
    setWeightSaveState('saving');
    const supabase = createClient();
    const { error } = await supabase
      .from('raw_measurements')
      .update({
        official_weight_kg: data.weightReal,
        official_metal_type: data.metalType,
        notes: data.notes || lotData.notes,
        status: 'processed',
      })
      .eq('id', lotData.id);

    if (error) {
      console.error('Error saving weight:', error.message);
      setWeightSaveState('idle');
      return;
    }
    setPriceFinal(computedPrice);
    setWeightSaveState('saved');
    setTimeout(() => setWeightSaveState('idle'), 2500);
  };

  const handleGenerateInvoice = async () => {
    if (!lotData) return;
    setInvoiceState('generating');
    const supabase = createClient();
    await supabase
      .from('raw_measurements')
      .update({ status: 'invoiced' })
      .eq('id', lotData.id);
    setTimeout(() => setInvoiceState('done'), 1500);
  };

  if (!selectedLotId) {
    return (
      <div className="bg-card rounded-xl border border-border flex items-center justify-center min-h-[400px]">
        <div className="text-center space-y-2">
          <Icon name="ClipboardDocumentListIcon" size={40} className="text-muted-foreground mx-auto" />
          <p className="text-sm text-muted-foreground">Sélectionnez un lot pour voir les détails</p>
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="bg-card rounded-xl border border-border overflow-hidden">
        <div className="px-5 py-4 border-b border-border">
          <div className="h-8 bg-muted rounded-lg animate-pulse w-48" />
        </div>
        <div className="p-5 space-y-4">
          {[1, 2, 3].map((i) => (
            <div key={`skel-${i}`} className="h-20 bg-muted rounded-lg animate-pulse" />
          ))}
        </div>
      </div>
    );
  }

  if (!lotData) {
    return (
      <div className="bg-card rounded-xl border border-border flex items-center justify-center min-h-[400px]">
        <div className="text-center space-y-2">
          <Icon name="ExclamationCircleIcon" size={40} className="text-muted-foreground mx-auto" />
          <p className="text-sm text-muted-foreground">Lot introuvable</p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 px-5 py-4 border-b border-border">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-secondary flex items-center justify-center">
            <Icon name="ClipboardDocumentListIcon" size={20} className="text-primary" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <span className="text-base font-700 text-primary tabular-nums">#{lotData.lotNumber}</span>
              <StatusBadge status={lotData.status} />
            </div>
            <p className="text-xs text-muted-foreground">{lotData.client} · {lotData.container}</p>
          </div>
        </div>
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <Icon name="ClockIcon" size={14} />
          <span>Soumis le {lotData.submittedAt}</span>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-border px-5">
        {(['detail', 'timeline'] as const).map((tab) => (
          <button
            key={`tab-${tab}`}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-3 text-sm font-600 border-b-2 transition-all ${
              activeTab === tab
                ? 'border-primary text-primary' :'border-transparent text-muted-foreground hover:text-foreground'
            }`}
          >
            {tab === 'detail' ? 'Détail & traitement' : 'Historique'}
          </button>
        ))}
      </div>

      <div className="p-5">
        {activeTab === 'detail' && (
          <div className="space-y-6">
            {/* Photo + AI side by side */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {/* Photo */}
              <div>
                <p className="text-xs font-600 text-muted-foreground uppercase tracking-wide mb-2">Photo du lot</p>
                <div className="relative rounded-xl overflow-hidden bg-gray-100 aspect-video">
                  {lotData.photoUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img
                      src={lotData.photoUrl}
                      alt={`Photo du lot ${lotData.lotNumber}`}
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center">
                      <Icon name="PhotoIcon" size={32} className="text-muted-foreground" />
                    </div>
                  )}
                </div>
              </div>

              {/* AI Result */}
              <div>
                <p className="text-xs font-600 text-muted-foreground uppercase tracking-wide mb-2">Résultat IA</p>
                <div className="bg-secondary rounded-xl p-4 space-y-3 h-full">
                  <div className="flex items-center gap-2">
                    <Icon name="SparklesIcon" size={16} className="text-primary" />
                    <span className="text-xs font-600 text-primary">Analyse automatique</span>
                    <span className="ml-auto text-xs font-600 text-muted-foreground tabular-nums">{lotData.confidence}% confiance</span>
                  </div>
                  <div className="h-1.5 bg-muted rounded-full overflow-hidden">
                    <div
                      className="h-full bg-accent rounded-full"
                      style={{ width: `${lotData.confidence}%` }}
                    />
                  </div>
                  <div className="space-y-2 pt-1">
                    <div className="flex justify-between text-sm">
                      <span className="text-muted-foreground">Type détecté</span>
                      <MetalBadge metal={lotData.metal} />
                    </div>
                    <div className="flex justify-between text-sm">
                      <span className="text-muted-foreground">Volume estimé</span>
                      <span className="font-600 tabular-nums">{lotData.volumeEstimated.toFixed(2)} m³</span>
                    </div>
                    <div className="flex justify-between text-sm">
                      <span className="text-muted-foreground">Prix estimé</span>
                      <span className="font-600 tabular-nums text-foreground">{lotData.priceEstimated.toFixed(2)} $CA</span>
                    </div>
                  </div>
                  {lotData.confidence < 80 && (
                    <div className="flex items-center gap-1.5 p-2 bg-amber-50 rounded-lg border border-amber-200">
                      <Icon name="ExclamationTriangleIcon" size={14} className="text-amber-600" />
                      <span className="text-xs text-amber-700">Confiance modérée — vérifiez le type</span>
                    </div>
                  )}
                </div>
              </div>
            </div>

            {/* Notes */}
            {lotData.notes && (
              <div className="p-4 bg-muted rounded-xl">
                <p className="text-xs font-600 text-muted-foreground uppercase tracking-wide mb-1">Notes client</p>
                <p className="text-sm text-foreground">{lotData.notes}</p>
              </div>
            )}

            {/* Weight entry form */}
            <form onSubmit={handleSubmit(onSave)} className="space-y-4">
              <div className="flex items-center gap-2 pb-2 border-b border-border">
                <Icon name="ScaleIcon" size={18} className="text-primary" />
                <h3 className="text-sm font-600 text-foreground">Saisie du poids réel</h3>
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-xs font-600 text-foreground mb-1.5">
                    Poids réel (kg) <span className="text-red-500">*</span>
                  </label>
                  <p className="text-xs text-muted-foreground mb-2">
                    Pesée sur balance certifiée après collecte
                  </p>
                  <div className="relative">
                    <input
                      type="number"
                      step="0.1"
                      min="0"
                      placeholder="0.0"
                      {...register('weightReal', {
                        required: 'Le poids réel est obligatoire',
                        min: { value: 0.1, message: 'Le poids minimum est 0.1 kg' }
                      })}
                      className="w-full px-4 py-2.5 pr-12 rounded-lg border border-border bg-input text-foreground text-sm tabular-nums focus:outline-none focus:ring-2 focus:ring-ring"
                    />
                    <span className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-muted-foreground font-600">kg</span>
                  </div>
                  {errors.weightReal && (
                    <p className="text-xs text-red-600 mt-1">{errors.weightReal.message}</p>
                  )}
                </div>

                <div>
                  <label className="block text-xs font-600 text-foreground mb-1.5">
                    Type de métal confirmé <span className="text-red-500">*</span>
                  </label>
                  <p className="text-xs text-muted-foreground mb-2">
                    Corrigez si l'IA s'est trompée
                  </p>
                  <select
                    {...register('metalType')}
                    className="w-full px-3 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring"
                  >
                    {Object.entries(METAL_PRICES).map(([m, p]) => (
                      <option key={`metal-opt-${m}`} value={m}>
                        {m.charAt(0).toUpperCase() + m.slice(1)} — {p.toFixed(2)} $CA/kg
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-xs font-600 text-foreground mb-1.5">Notes opérateur</label>
                <textarea
                  {...register('notes')}
                  rows={2}
                  placeholder="Observations sur le lot, état du métal, tri effectué..."
                  className="w-full px-4 py-3 rounded-lg border border-border bg-input text-foreground text-sm resize-none focus:outline-none focus:ring-2 focus:ring-ring placeholder:text-muted-foreground"
                />
              </div>

              {/* Price comparison */}
              {computedPrice !== null && (
                <div className="bg-muted rounded-xl p-4 fade-in-up">
                  <p className="text-xs font-600 text-muted-foreground uppercase tracking-wide mb-3">
                    Comparaison estimation vs réel
                  </p>
                  <div className="grid grid-cols-3 gap-3">
                    <div className="text-center p-3 bg-card rounded-lg">
                      <p className="text-[11px] text-muted-foreground mb-1">Prix estimé IA</p>
                      <p className="text-base font-700 tabular-nums text-muted-foreground">
                        {lotData.priceEstimated.toFixed(2)} $CA
                      </p>
                    </div>
                    <div className="text-center p-3 bg-card rounded-lg flex flex-col items-center justify-center">
                      <Icon name="ArrowRightIcon" size={20} className="text-muted-foreground" />
                    </div>
                    <div className="text-center p-3 bg-secondary rounded-lg border border-primary/20">
                      <p className="text-[11px] text-primary mb-1">Prix final réel</p>
                      <p className="text-base font-700 tabular-nums text-primary">
                        {computedPrice.toFixed(2)} $CA
                      </p>
                      {computedPrice !== lotData.priceEstimated && (
                        <p className={`text-[11px] tabular-nums font-600 ${computedPrice > lotData.priceEstimated ? 'text-green-600' : 'text-red-500'}`}>
                          {computedPrice > lotData.priceEstimated ? '+' : ''}{(computedPrice - lotData.priceEstimated).toFixed(2)} $CA
                        </p>
                      )}
                    </div>
                  </div>
                  <p className="text-[11px] text-muted-foreground mt-2 text-center">
                    {watchedWeight} kg × {METAL_PRICES[watchedMetal]?.toFixed(2)} $CA/kg = {computedPrice.toFixed(2)} $CA
                  </p>
                </div>
              )}

              <div className="flex gap-3">
                <button
                  type="submit"
                  disabled={weightSaveState === 'saving'}
                  className={`flex-1 py-3 rounded-xl text-sm font-600 flex items-center justify-center gap-2 transition-all ${
                    weightSaveState === 'saved' ? 'bg-secondary text-primary border border-primary/20' : 'btn-primary'
                  } disabled:opacity-70`}
                >
                  {weightSaveState === 'saving' ? (
                    <>
                      <Icon name="ArrowPathIcon" size={16} className="text-primary-foreground animate-spin" />
                      Enregistrement...
                    </>
                  ) : weightSaveState === 'saved' ? (
                    <>
                      <Icon name="CheckCircleIcon" size={16} className="text-primary" />
                      Enregistré ✓
                    </>
                  ) : (
                    <>
                      <Icon name="CheckIcon" size={16} className="text-primary-foreground" />
                      Enregistrer le poids
                    </>
                  )}
                </button>
              </div>
            </form>

            {/* Invoice generation */}
            <div className="border-t border-border pt-5">
              <div className="flex items-center gap-2 mb-3">
                <Icon name="DocumentTextIcon" size={18} className="text-primary" />
                <h3 className="text-sm font-600 text-foreground">Génération de facture</h3>
              </div>

              {priceFinal !== null ? (
                <div className="space-y-3">
                  <div className="flex items-center justify-between p-4 bg-secondary rounded-xl border border-primary/20">
                    <div>
                      <p className="text-xs text-muted-foreground">Montant à facturer</p>
                      <p className="text-2xl font-700 tabular-nums text-primary mt-0.5">
                        {priceFinal.toFixed(2)} $CA
                      </p>
                    </div>
                    <div className="text-right">
                      <p className="text-xs text-muted-foreground">Client</p>
                      <p className="text-sm font-600 text-foreground">{lotData.client}</p>
                    </div>
                  </div>

                  <button
                    onClick={handleGenerateInvoice}
                    disabled={invoiceState !== 'idle'}
                    className={`w-full py-3 rounded-xl text-sm font-600 flex items-center justify-center gap-2 transition-all ${
                      invoiceState === 'done'
                        ? 'bg-secondary text-primary border border-primary/20' :'btn-accent'
                    } disabled:opacity-70`}
                  >
                    {invoiceState === 'generating' ? (
                      <>
                        <Icon name="ArrowPathIcon" size={16} className="text-accent-foreground animate-spin" />
                        Génération en cours...
                      </>
                    ) : invoiceState === 'done' ? (
                      <>
                        <Icon name="CheckCircleIcon" size={16} className="text-primary" />
                        Facture générée ✓
                      </>
                    ) : (
                      <>
                        <Icon name="DocumentPlusIcon" size={16} className="text-accent-foreground" />
                        Générer la facture
                      </>
                    )}
                  </button>
                </div>
              ) : (
                <div className="p-4 bg-muted rounded-xl flex items-center gap-3">
                  <Icon name="InformationCircleIcon" size={18} className="text-muted-foreground" />
                  <p className="text-sm text-muted-foreground">
                    Saisissez et enregistrez le poids réel pour activer la génération de facture.
                  </p>
                </div>
              )}
            </div>
          </div>
        )}

        {activeTab === 'timeline' && (
          <div className="space-y-4">
            <div className="relative">
              <div className="absolute left-4 top-0 bottom-0 w-0.5 bg-border" />
              <div className="space-y-4">
                <div className="flex gap-4 relative">
                  <div className="w-8 h-8 rounded-full bg-primary flex items-center justify-center flex-shrink-0 z-10">
                    <Icon name="ClipboardDocumentListIcon" size={14} className="text-primary-foreground" />
                  </div>
                  <div className="flex-1 pb-4">
                    <p className="text-sm font-600 text-foreground">Lot soumis</p>
                    <p className="text-xs text-muted-foreground mt-0.5">Client</p>
                    <p className="text-xs text-muted-foreground tabular-nums">{lotData.submittedAt}</p>
                  </div>
                </div>
                <div className="flex gap-4 relative">
                  <div className="w-8 h-8 rounded-full bg-muted border-2 border-border flex items-center justify-center flex-shrink-0 z-10">
                    <Icon name="SparklesIcon" size={14} className="text-muted-foreground" />
                  </div>
                  <div className="flex-1 pb-4">
                    <p className="text-sm font-600 text-foreground">Analyse IA complétée</p>
                    <p className="text-xs text-muted-foreground mt-0.5">IA METALTRACE</p>
                    <p className="text-xs text-muted-foreground tabular-nums">{lotData.submittedAt}</p>
                  </div>
                </div>
                {/* Pending step */}
                <div className="flex gap-4 relative">
                  <div className="w-8 h-8 rounded-full bg-muted border-2 border-dashed border-border flex items-center justify-center flex-shrink-0 z-10">
                    <Icon name="ScaleIcon" size={14} className="text-muted-foreground" />
                  </div>
                  <div className="flex-1 pb-4">
                    <p className="text-sm font-600 text-muted-foreground">En attente : saisie du poids réel</p>
                    <p className="text-xs text-muted-foreground mt-0.5">Opérateur METALTRACE</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}