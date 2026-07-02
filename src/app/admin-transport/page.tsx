'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';
import AppLayout from '@/components/AppLayout';

// ─── Types ───────────────────────────────────────────────────────────────────

interface TransportRequest {
  id: string;
  lot_id: string;
  container_id: string | null;
  pickup_address: string;
  dropoff_address: string;
  arrival_eta: string | null;
  scheduled_time: string | null;
  provider: string;
  transporter: string;
  driver_name: string | null;
  truck_number: string | null;
  transport_mode: string | null;
  transport_status: string;
  proof_photo_url: string | null;
  proof_document_url: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

interface PendingLot {
  id: string;
  container_id: string | null;
  metal_type: string | null;
  weight_kg: number | null;
  created_at: string;
  container_name: string | null;
  container_location: string | null;
}

interface CreateTransportForm {
  pickup_address: string;
  dropoff_address: string;
  transport_mode: string;
  driver_name: string;
  truck_number: string;
  scheduled_time: string;
  notes: string;
}

// ─── Constants ───────────────────────────────────────────────────────────────

const STATUS_OPTIONS = [
  { value: 'all', label: 'Tous les statuts' },
  { value: 'scheduled', label: 'Planifié' },
  { value: 'in_transit', label: 'En transit' },
  { value: 'arrived', label: 'Arrivé' },
  { value: 'delivered', label: 'Livré' },
  { value: 'cancelled', label: 'Annulé' },
];

const STATUS_COLORS: Record<string, string> = {
  scheduled:  'text-amber-700 bg-amber-50 border-amber-200',
  in_transit: 'text-indigo-700 bg-indigo-50 border-indigo-200',
  arrived:    'text-purple-700 bg-purple-50 border-purple-200',
  delivered:  'text-green-700 bg-green-50 border-green-200',
  cancelled:  'text-red-700 bg-red-50 border-red-200',
};

const STATUS_LABELS: Record<string, string> = {
  scheduled: 'Planifié', in_transit: 'En transit', arrived: 'Arrivé',
  delivered: 'Livré', cancelled: 'Annulé',
};

const VALID_STATUSES = ['scheduled', 'in_transit', 'arrived', 'delivered', 'cancelled'];

const TRANSPORT_MODES = [
  { value: 'camion', label: 'Camion' },
  { value: 'train', label: 'Train' },
  { value: 'navire', label: 'Navire' },
];

const DEFAULT_DROPOFF = '3500 boul. Industriel, Laval, QC H7L 4R3';

// ─── Sub-components ───────────────────────────────────────────────────────────

function TransportStatusBadge({ status }: { status: string }) {
  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-600 border ${STATUS_COLORS[status] ?? 'text-muted-foreground bg-muted border-border'}`}>
      {STATUS_LABELS[status] ?? status}
    </span>
  );
}

interface DetailModalProps {
  transport: TransportRequest;
  onClose: () => void;
  onStatusUpdate: (id: string, newStatus: string) => Promise<void>;
}

function DetailModal({ transport, onClose, onStatusUpdate }: DetailModalProps) {
  const [selectedStatus, setSelectedStatus] = useState(transport.transport_status);
  const [updating, setUpdating] = useState(false);
  const [updateMsg, setUpdateMsg] = useState<string | null>(null);

  const handleUpdate = async () => {
    if (selectedStatus === transport.transport_status) return;
    setUpdating(true);
    setUpdateMsg(null);
    try {
      await onStatusUpdate(transport.id, selectedStatus);
      setUpdateMsg('Statut mis à jour avec succès.');
    } catch (e: unknown) {
      setUpdateMsg(e instanceof Error ? e.message : 'Erreur lors de la mise à jour.');
    } finally {
      setUpdating(false);
    }
  };

  const isInternal = transport.provider === 'internal';

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50">
      <div className="bg-card rounded-2xl border border-border w-full max-w-lg shadow-xl overflow-hidden max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between px-5 py-4 border-b border-border sticky top-0 bg-card z-10">
          <div className="flex items-center gap-3">
            <Icon name="TruckIcon" size={18} className="text-primary" />
            <h2 className="text-base font-700 text-foreground">Détail transport</h2>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg btn-ghost">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>
        <div className="p-5 space-y-4">
          <div className={`flex items-center gap-2 px-3 py-2 rounded-lg ${isInternal ? 'bg-secondary' : 'bg-muted'}`}>
            <Icon name="TruckIcon" size={14} className="text-primary" />
            <span className="text-xs font-600 text-primary">
              {isInternal ? 'Transport interne METALTRACE' : 'Transport du client'}
            </span>
          </div>
          <div className="grid grid-cols-2 gap-3">
            {[
              { label: 'Lot', value: `#${transport.lot_id.slice(0, 8).toUpperCase()}` },
              { label: 'Conteneur', value: transport.container_id ?? '—' },
              { label: 'Chauffeur', value: transport.driver_name ?? '—' },
              { label: 'Camion', value: transport.truck_number ?? '—' },
              { label: 'Mode', value: transport.transport_mode ?? '—' },
              { label: 'Transporteur', value: transport.transporter },
            ].map(({ label, value }) => (
              <div key={label} className="bg-muted rounded-lg p-3">
                <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-0.5">{label}</p>
                <p className="text-sm font-600 text-foreground">{value}</p>
              </div>
            ))}
          </div>
          {transport.arrival_eta && (
            <div className="flex items-center gap-2 p-3 bg-muted rounded-lg">
              <Icon name="CalendarIcon" size={14} className="text-primary flex-shrink-0" />
              <div>
                <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide">ETA d&apos;arrivée</p>
                <p className="text-sm font-600 text-foreground tabular-nums">
                  {new Date(transport.arrival_eta).toLocaleString('fr-CA', { dateStyle: 'medium', timeStyle: 'short' })}
                </p>
              </div>
            </div>
          )}
          {transport.notes && (
            <div className="p-3 bg-muted rounded-lg">
              <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-1">Notes</p>
              <p className="text-sm text-foreground">{transport.notes}</p>
            </div>
          )}
          {(transport.proof_photo_url || transport.proof_document_url) && (
            <div className="space-y-2">
              <p className="text-xs font-600 text-foreground">Preuves</p>
              <div className="flex flex-wrap gap-2">
                {transport.proof_photo_url && (
                  <a href={transport.proof_photo_url} target="_blank" rel="noopener noreferrer"
                    className="flex items-center gap-1.5 px-3 py-2 bg-muted rounded-lg text-xs font-600 text-foreground hover:bg-secondary transition-colors">
                    <Icon name="PhotoIcon" size={12} />Photo de preuve
                  </a>
                )}
                {transport.proof_document_url && (
                  <a href={transport.proof_document_url} target="_blank" rel="noopener noreferrer"
                    className="flex items-center gap-1.5 px-3 py-2 bg-muted rounded-lg text-xs font-600 text-foreground hover:bg-secondary transition-colors">
                    <Icon name="DocumentTextIcon" size={12} />Document
                  </a>
                )}
              </div>
            </div>
          )}
          <div className="border-t border-border pt-4">
            <p className="text-xs font-600 text-foreground mb-2">Mise à jour manuelle du statut</p>
            <div className="flex gap-2">
              <select
                value={selectedStatus}
                onChange={(e) => setSelectedStatus(e.target.value)}
                className="flex-1 px-3 py-2 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring"
              >
                {VALID_STATUSES.map((s) => (
                  <option key={s} value={s}>{STATUS_LABELS[s]}</option>
                ))}
              </select>
              <button
                onClick={handleUpdate}
                disabled={updating || selectedStatus === transport.transport_status}
                className="px-4 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-600 btn-primary disabled:opacity-50"
              >
                {updating ? 'Mise à jour…' : 'Mettre à jour'}
              </button>
            </div>
            {updateMsg && (
              <p className={`text-xs mt-2 ${updateMsg.includes('succès') ? 'text-green-600' : 'text-red-600'}`}>
                {updateMsg}
              </p>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Create Transport Modal ───────────────────────────────────────────────────

interface CreateTransportModalProps {
  lot: PendingLot;
  onClose: () => void;
  onSuccess: () => void;
}

function CreateTransportModal({ lot, onClose, onSuccess }: CreateTransportModalProps) {
  const supabase = createClient();
  const [form, setForm] = useState<CreateTransportForm>({
    pickup_address: '',
    dropoff_address: DEFAULT_DROPOFF,
    transport_mode: 'camion',
    driver_name: '',
    truck_number: '',
    scheduled_time: '',
    notes: '',
  });
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [calcResult, setCalcResult] = useState<{ distance_km: number; ghg_transport_kgco2e: number } | null>(null);

  const handleChange = (field: keyof CreateTransportForm, value: string) => {
    setForm((prev) => ({ ...prev, [field]: value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    setCalcResult(null);

    try {
      // Step 1: Get current user's company_id
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Utilisateur non authentifié');

      const { data: memberData, error: memberError } = await supabase
        .from('company_members')
        .select('company_id')
        .eq('user_id', user.id)
        .limit(1)
        .single();

      if (memberError || !memberData) throw new Error('Impossible de récupérer la compagnie de l\'utilisateur');

      const company_id = memberData.company_id;
      const weight_kg = lot.weight_kg ?? 0;

      // Step 2: Call calculate-distance API
      const distRes = await fetch('/api/transport/calculate-distance', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          pickup_address: form.pickup_address,
          dropoff_address: form.dropoff_address,
          weight_kg: weight_kg > 0 ? weight_kg : 1, // API requires > 0
        }),
      });

      let distance_km: number | null = null;
      let ghg_transport_kgco2e: number | null = null;
      let emission_factor_used: number | null = null;

      if (distRes.ok) {
        const distData = await distRes.json();
        distance_km = distData.distance_km ?? null;
        ghg_transport_kgco2e = distData.ghg_transport_kgco2e ?? null;
        emission_factor_used = distData.emission_factor_used ?? null;
        setCalcResult({ distance_km: distData.distance_km, ghg_transport_kgco2e: distData.ghg_transport_kgco2e });
      }
      // If distance calc fails, we continue without it (non-blocking)

      // Step 3: Insert into transport_requests
      const insertPayload: Record<string, unknown> = {
        lot_id: lot.id,
        company_id,
        container_id: lot.container_id ?? null,
        pickup_address: form.pickup_address,
        dropoff_address: form.dropoff_address,
        transport_mode: form.transport_mode,
        driver_name: form.driver_name || null,
        truck_number: form.truck_number || null,
        scheduled_time: form.scheduled_time || null,
        notes: form.notes || null,
        weight_tonnes: (weight_kg ?? 0) / 1000,
        transporter: 'METALTRACE',
        provider: 'internal',
        transport_status: 'scheduled',
      };

      if (distance_km !== null) insertPayload.distance_km = distance_km;
      if (ghg_transport_kgco2e !== null) insertPayload.ghg_transport_kgco2e = ghg_transport_kgco2e;
      if (emission_factor_used !== null) insertPayload.emission_factor_used = emission_factor_used;

      const { data: newTransport, error: insertError } = await supabase
        .from('transport_requests')
        .insert(insertPayload)
        .select('id')
        .single();

      if (insertError) throw new Error(`Erreur lors de la création du transport : ${insertError.message}`);

      // Step 4: Update raw_measurements.transport_request_id
      const { error: updateError } = await supabase
        .from('raw_measurements')
        .update({ transport_request_id: newTransport.id })
        .eq('id', lot.id);

      if (updateError) throw new Error(`Transport créé mais erreur de liaison au lot : ${updateError.message}`);

      onSuccess();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Erreur inconnue');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50">
      <div className="bg-card rounded-2xl border border-border w-full max-w-lg shadow-xl overflow-hidden max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-border sticky top-0 bg-card z-10">
          <div className="flex items-center gap-3">
            <Icon name="TruckIcon" size={18} className="text-primary" />
            <div>
              <h2 className="text-base font-700 text-foreground">Créer un transport</h2>
              <p className="text-xs text-muted-foreground">Lot #{lot.id.slice(0, 8).toUpperCase()} — {lot.container_name ?? 'Conteneur inconnu'}</p>
            </div>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg btn-ghost">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {/* Lot summary */}
          <div className="grid grid-cols-3 gap-2 p-3 bg-muted rounded-xl">
            <div>
              <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-0.5">Métal</p>
              <p className="text-sm font-600 text-foreground">{lot.metal_type ?? '—'}</p>
            </div>
            <div>
              <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-0.5">Poids</p>
              <p className="text-sm font-600 text-foreground tabular-nums">{lot.weight_kg != null ? `${lot.weight_kg} kg` : '—'}</p>
            </div>
            <div>
              <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-0.5">Poids (t)</p>
              <p className="text-sm font-600 text-foreground tabular-nums">{((lot.weight_kg ?? 0) / 1000).toFixed(4)} t</p>
            </div>
          </div>

          {/* pickup_address */}
          <div>
            <label className="block text-xs font-600 text-foreground mb-1.5">
              Adresse de ramassage <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              required
              value={form.pickup_address}
              onChange={(e) => handleChange('pickup_address', e.target.value)}
              placeholder="Ex: 1250 rue Notre-Dame Ouest, Montréal, QC H3C 1K4"
              className="w-full px-3 py-2 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>

          {/* dropoff_address */}
          <div>
            <label className="block text-xs font-600 text-foreground mb-1.5">
              Adresse de destination <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              required
              value={form.dropoff_address}
              onChange={(e) => handleChange('dropoff_address', e.target.value)}
              className="w-full px-3 py-2 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>

          {/* transport_mode */}
          <div>
            <label className="block text-xs font-600 text-foreground mb-1.5">Mode de transport</label>
            <select
              value={form.transport_mode}
              onChange={(e) => handleChange('transport_mode', e.target.value)}
              className="w-full px-3 py-2 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            >
              {TRANSPORT_MODES.map((m) => (
                <option key={m.value} value={m.value}>{m.label}</option>
              ))}
            </select>
          </div>

          {/* driver_name + truck_number */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-600 text-foreground mb-1.5">Nom du conducteur</label>
              <input
                type="text"
                value={form.driver_name}
                onChange={(e) => handleChange('driver_name', e.target.value)}
                placeholder="Jean Tremblay"
                className="w-full px-3 py-2 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring"
              />
            </div>
            <div>
              <label className="block text-xs font-600 text-foreground mb-1.5">Numéro du camion</label>
              <input
                type="text"
                value={form.truck_number}
                onChange={(e) => handleChange('truck_number', e.target.value)}
                placeholder="QC-1234-AB"
                className="w-full px-3 py-2 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring"
              />
            </div>
          </div>

          {/* scheduled_time */}
          <div>
            <label className="block text-xs font-600 text-foreground mb-1.5">Date/heure prévue</label>
            <input
              type="datetime-local"
              value={form.scheduled_time}
              onChange={(e) => handleChange('scheduled_time', e.target.value)}
              className="w-full px-3 py-2 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>

          {/* notes */}
          <div>
            <label className="block text-xs font-600 text-foreground mb-1.5">Notes (optionnel)</label>
            <textarea
              value={form.notes}
              onChange={(e) => handleChange('notes', e.target.value)}
              rows={2}
              placeholder="Informations supplémentaires…"
              className="w-full px-3 py-2 rounded-lg border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring resize-none"
            />
          </div>

          {/* Calc result preview */}
          {calcResult && (
            <div className="flex items-center gap-3 p-3 bg-green-50 border border-green-200 rounded-xl">
              <Icon name="CheckCircleIcon" size={16} className="text-green-600 flex-shrink-0" />
              <div className="text-xs text-green-700">
                <span className="font-600">Distance calculée :</span> {calcResult.distance_km} km —{' '}
                <span className="font-600">GES :</span> {calcResult.ghg_transport_kgco2e} kgCO₂e
              </div>
            </div>
          )}

          {/* Error */}
          {error && (
            <div className="flex items-start gap-2 p-3 bg-red-50 border border-red-200 rounded-xl">
              <Icon name="ExclamationCircleIcon" size={16} className="text-red-600 flex-shrink-0 mt-0.5" />
              <p className="text-xs text-red-700">{error}</p>
            </div>
          )}

          {/* Actions */}
          <div className="flex gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 px-4 py-2.5 rounded-lg border border-border text-sm font-600 text-foreground btn-ghost"
            >
              Annuler
            </button>
            <button
              type="submit"
              disabled={submitting}
              className="flex-1 px-4 py-2.5 rounded-lg bg-primary text-primary-foreground text-sm font-600 btn-primary disabled:opacity-50 flex items-center justify-center gap-2"
            >
              {submitting ? (
                <>
                  <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24" fill="none">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z" />
                  </svg>
                  Création…
                </>
              ) : (
                <>
                  <Icon name="TruckIcon" size={14} className="text-primary-foreground" />
                  Créer le transport
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function AdminTransportPage() {
  const supabase = createClient();

  // Existing transports state
  const [transports, setTransports] = useState<TransportRequest[]>([]);
  const [loadingTransports, setLoadingTransports] = useState(true);
  const [transportsError, setTransportsError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState('all');
  const [providerFilter, setProviderFilter] = useState('all');
  const [selectedTransport, setSelectedTransport] = useState<TransportRequest | null>(null);

  // Pending lots state
  const [pendingLots, setPendingLots] = useState<PendingLot[]>([]);
  const [loadingLots, setLoadingLots] = useState(true);
  const [lotsError, setLotsError] = useState<string | null>(null);
  const [selectedLot, setSelectedLot] = useState<PendingLot | null>(null);

  // ── Fetch transports ──────────────────────────────────────────────────────
  const fetchTransports = useCallback(async () => {
    setLoadingTransports(true);
    setTransportsError(null);
    try {
      let query = supabase
        .from('transport_requests')
        .select('*')
        .order('created_at', { ascending: false });

      if (statusFilter !== 'all') query = query.eq('transport_status', statusFilter);
      if (providerFilter !== 'all') query = query.eq('provider', providerFilter);

      const { data, error: fetchError } = await query;
      if (fetchError) setTransportsError(fetchError.message);
      else setTransports(data ?? []);
    } finally {
      setLoadingTransports(false);
    }
  }, [statusFilter, providerFilter, supabase]);

  // ── Fetch pending lots ────────────────────────────────────────────────────
  const fetchPendingLots = useCallback(async () => {
    setLoadingLots(true);
    setLotsError(null);
    try {
      const { data, error: fetchError } = await supabase
        .from('raw_measurements')
        .select(`
          id,
          container_id,
          metal_type_predicted,
          weight_kg,
          created_at,
          containers (
            name,
            location
          )
        `)
        .eq('status', 'submitted')
        .is('transport_request_id', null)
        .order('created_at', { ascending: false });

      if (fetchError) {
        setLotsError(fetchError.message);
      } else {
        const mapped: PendingLot[] = (data ?? []).map((row: Record<string, unknown>) => {
          const container = row.containers as { name: string; location: string | null } | null;
          return {
            id: row.id as string,
            container_id: row.container_id as string | null,
            metal_type: row.metal_type_predicted as string | null,
            weight_kg: row.weight_kg as number | null,
            created_at: row.created_at as string,
            container_name: container?.name ?? null,
            container_location: container?.location ?? null,
          };
        });
        setPendingLots(mapped);
      }
    } finally {
      setLoadingLots(false);
    }
  }, [supabase]);

  useEffect(() => {
    fetchTransports();
    fetchPendingLots();

    const channel = supabase
      .channel('admin_transport_page')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'transport_requests' }, () => {
        fetchTransports();
      })
      .on('postgres_changes', { event: '*', schema: 'public', table: 'raw_measurements' }, () => {
        fetchPendingLots();
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [fetchTransports, fetchPendingLots, supabase]);

  const handleStatusUpdate = async (id: string, newStatus: string) => {
    const res = await fetch('/api/transport/update-status', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ transport_id: id, new_status: newStatus }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error ?? 'Erreur');
    await fetchTransports();
    if (selectedTransport) {
      setSelectedTransport((prev) => prev ? { ...prev, transport_status: newStatus } : null);
    }
  };

  const handleTransportCreated = async () => {
    setSelectedLot(null);
    await Promise.all([fetchTransports(), fetchPendingLots()]);
  };

  const kpis = {
    total: transports.length,
    active: transports.filter(t => !['delivered', 'cancelled'].includes(t.transport_status)).length,
    delivered: transports.filter(t => t.transport_status === 'delivered').length,
    pending: pendingLots.length,
  };

  return (
    <AppLayout userRole="admin" activeRoute="/admin-transport">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 py-8 space-y-8">

        {/* ── Page Header ── */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-primary flex items-center justify-center">
              <Icon name="TruckIcon" size={20} className="text-primary-foreground" />
            </div>
            <div>
              <h1 className="text-xl font-700 text-foreground">Gestion des transports</h1>
              <p className="text-sm text-muted-foreground">METALTRACE — Planification et suivi</p>
            </div>
          </div>
        </div>

        {/* ── KPI Cards ── */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          {[
            { label: 'Total transports', value: kpis.total, color: 'text-foreground' },
            { label: 'En cours', value: kpis.active, color: 'text-blue-600' },
            { label: 'Livrés', value: kpis.delivered, color: 'text-green-600' },
            { label: 'Lots en attente', value: kpis.pending, color: 'text-amber-600' },
          ].map((kpi) => (
            <div key={kpi.label} className="bg-card border border-border rounded-xl p-4">
              <p className="text-xs text-muted-foreground font-500 mb-1">{kpi.label}</p>
              <p className={`text-2xl font-700 tabular-nums ${kpi.color}`}>{kpi.value}</p>
            </div>
          ))}
        </div>

        {/* ══════════════════════════════════════════════════════════════════
            SECTION 1 — Lots en attente de transport
        ══════════════════════════════════════════════════════════════════ */}
        <section>
          <div className="flex items-center gap-2 mb-4">
            <div className="w-1 h-5 bg-amber-500 rounded-full" />
            <h2 className="text-base font-700 text-foreground">Lots en attente de transport</h2>
            {pendingLots.length > 0 && (
              <span className="ml-1 bg-amber-100 text-amber-700 border border-amber-200 text-[11px] font-700 px-2 py-0.5 rounded-full tabular-nums">
                {pendingLots.length}
              </span>
            )}
          </div>

          {lotsError && (
            <div className="flex items-center gap-2 p-4 bg-red-50 border border-red-200 rounded-xl mb-4">
              <Icon name="ExclamationCircleIcon" size={16} className="text-red-600" />
              <p className="text-sm text-red-700">{lotsError}</p>
            </div>
          )}

          <div className="bg-card border border-border rounded-xl overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border bg-muted/40">
                    {['ID Lot', 'Conteneur', 'Métal', 'Poids estimé', 'Date soumission', 'Action'].map((h) => (
                      <th key={h} className="px-4 py-3 text-left text-[11px] font-600 text-muted-foreground uppercase tracking-wide whitespace-nowrap">
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {loadingLots ? (
                    Array.from({ length: 3 }).map((_, i) => (
                      <tr key={i} className="border-b border-border">
                        {Array.from({ length: 6 }).map((_, j) => (
                          <td key={j} className="px-4 py-3">
                            <div className="h-4 bg-muted rounded animate-pulse w-20" />
                          </td>
                        ))}
                      </tr>
                    ))
                  ) : pendingLots.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="px-4 py-12 text-center">
                        <div className="flex flex-col items-center gap-2">
                          <Icon name="CheckCircleIcon" size={32} className="text-green-500" />
                          <p className="text-sm font-600 text-foreground">Aucun lot en attente</p>
                          <p className="text-xs text-muted-foreground">Tous les lots soumis ont déjà un transport assigné.</p>
                        </div>
                      </td>
                    </tr>
                  ) : (
                    pendingLots.map((lot) => (
                      <tr key={lot.id} className="border-b border-border last:border-0 row-hover">
                        <td className="px-4 py-3">
                          <span className="font-700 text-primary text-xs tabular-nums">#{lot.id.slice(0, 8).toUpperCase()}</span>
                        </td>
                        <td className="px-4 py-3">
                          <span className="text-xs bg-muted px-2 py-0.5 rounded font-500">
                            {lot.container_name ?? lot.container_id?.slice(0, 8) ?? '—'}
                          </span>
                        </td>
                        <td className="px-4 py-3">
                          <span className="text-xs font-500 text-foreground">{lot.metal_type ?? '—'}</span>
                        </td>
                        <td className="px-4 py-3">
                          <span className="text-xs tabular-nums text-foreground font-500">
                            {lot.weight_kg != null ? `${lot.weight_kg} kg` : '—'}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-xs text-muted-foreground tabular-nums whitespace-nowrap">
                          {new Date(lot.created_at).toLocaleDateString('fr-CA', { dateStyle: 'medium' })}
                        </td>
                        <td className="px-4 py-3">
                          <button
                            onClick={() => setSelectedLot(lot)}
                            className="flex items-center gap-1.5 px-3 py-1.5 bg-primary text-primary-foreground rounded-lg text-xs font-600 btn-primary whitespace-nowrap"
                          >
                            <Icon name="TruckIcon" size={12} className="text-primary-foreground" />
                            Créer un transport
                          </button>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </section>

        {/* ══════════════════════════════════════════════════════════════════
            SECTION 2 — Demandes de transport existantes
        ══════════════════════════════════════════════════════════════════ */}
        <section>
          <div className="flex items-center gap-2 mb-4">
            <div className="w-1 h-5 bg-primary rounded-full" />
            <h2 className="text-base font-700 text-foreground">Demandes de transport</h2>
          </div>

          {/* Filters */}
          <div className="flex flex-wrap items-center gap-2 mb-4">
            <Icon name="FunnelIcon" size={14} className="text-muted-foreground" />
            {STATUS_OPTIONS.map((opt) => (
              <button
                key={opt.value}
                onClick={() => setStatusFilter(opt.value)}
                className={`px-3 py-1.5 rounded-lg text-xs font-600 border transition-all ${
                  statusFilter === opt.value
                    ? 'bg-primary text-primary-foreground border-primary'
                    : 'bg-card text-muted-foreground border-border btn-ghost'
                }`}
              >
                {opt.label}
              </button>
            ))}
            <div className="w-px h-4 bg-border mx-1" />
            {[
              { value: 'all', label: 'Tous' },
              { value: 'internal', label: 'Interne METALTRACE' },
              { value: 'client', label: 'Transport client' },
            ].map((opt) => (
              <button
                key={opt.value}
                onClick={() => setProviderFilter(opt.value)}
                className={`px-3 py-1.5 rounded-lg text-xs font-600 border transition-all ${
                  providerFilter === opt.value
                    ? 'bg-secondary text-primary border-primary' :'bg-card text-muted-foreground border-border btn-ghost'
                }`}
              >
                {opt.label}
              </button>
            ))}
          </div>

          {transportsError && (
            <div className="flex items-center gap-2 p-4 bg-red-50 border border-red-200 rounded-xl mb-4">
              <Icon name="ExclamationCircleIcon" size={16} className="text-red-600" />
              <p className="text-sm text-red-700">{transportsError}</p>
            </div>
          )}

          <div className="bg-card border border-border rounded-xl overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border bg-muted/40">
                    {['Lot', 'Conteneur', 'Type', 'Chauffeur / Transporteur', 'Camion', 'Statut', 'ETA', 'Preuves', 'Actions'].map((h) => (
                      <th key={h} className="px-4 py-3 text-left text-[11px] font-600 text-muted-foreground uppercase tracking-wide whitespace-nowrap">
                        {h}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {loadingTransports ? (
                    Array.from({ length: 4 }).map((_, i) => (
                      <tr key={i} className="border-b border-border">
                        {Array.from({ length: 9 }).map((_, j) => (
                          <td key={j} className="px-4 py-3">
                            <div className="h-4 bg-muted rounded animate-pulse w-20" />
                          </td>
                        ))}
                      </tr>
                    ))
                  ) : transports.length === 0 ? (
                    <tr>
                      <td colSpan={9} className="px-4 py-12 text-center text-sm text-muted-foreground">
                        Aucune demande de transport trouvée.
                      </td>
                    </tr>
                  ) : (
                    transports.map((t) => (
                      <tr key={t.id} className="border-b border-border last:border-0 row-hover">
                        <td className="px-4 py-3">
                          <span className="font-600 text-primary text-xs tabular-nums">#{t.lot_id.slice(0, 8).toUpperCase()}</span>
                        </td>
                        <td className="px-4 py-3">
                          <span className="text-xs bg-muted px-2 py-0.5 rounded font-500">{t.container_id ?? '—'}</span>
                        </td>
                        <td className="px-4 py-3">
                          <span className={`text-xs font-600 px-2 py-0.5 rounded-full ${t.provider === 'internal' ? 'text-primary bg-secondary' : 'text-muted-foreground bg-muted'}`}>
                            {t.provider === 'internal' ? 'Interne' : 'Client'}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-xs text-foreground whitespace-nowrap">
                          {t.driver_name ?? t.transporter ?? '—'}
                        </td>
                        <td className="px-4 py-3 text-xs text-muted-foreground">{t.truck_number ?? '—'}</td>
                        <td className="px-4 py-3">
                          <TransportStatusBadge status={t.transport_status} />
                        </td>
                        <td className="px-4 py-3 text-xs text-muted-foreground tabular-nums whitespace-nowrap">
                          {(t.arrival_eta || t.scheduled_time)
                            ? new Date(t.arrival_eta ?? t.scheduled_time!).toLocaleString('fr-CA', { dateStyle: 'short', timeStyle: 'short' })
                            : '—'}
                        </td>
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-1">
                            {t.proof_photo_url && (
                              <a href={t.proof_photo_url} target="_blank" rel="noopener noreferrer" title="Photo de preuve">
                                <Icon name="PhotoIcon" size={14} className="text-primary hover:text-primary/70" />
                              </a>
                            )}
                            {t.proof_document_url && (
                              <a href={t.proof_document_url} target="_blank" rel="noopener noreferrer" title="Document de preuve">
                                <Icon name="DocumentTextIcon" size={14} className="text-primary hover:text-primary/70" />
                              </a>
                            )}
                            {!t.proof_photo_url && !t.proof_document_url && (
                              <span className="text-xs text-muted-foreground">—</span>
                            )}
                          </div>
                        </td>
                        <td className="px-4 py-3">
                          <button
                            onClick={() => setSelectedTransport(t)}
                            className="flex items-center gap-1.5 px-3 py-1.5 bg-primary text-primary-foreground rounded-lg text-xs font-600 btn-primary whitespace-nowrap"
                          >
                            <Icon name="PencilSquareIcon" size={12} className="text-primary-foreground" />
                            Détails
                          </button>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </section>
      </div>

      {/* ── Modals ── */}
      {selectedTransport && (
        <DetailModal
          transport={selectedTransport}
          onClose={() => setSelectedTransport(null)}
          onStatusUpdate={handleStatusUpdate}
        />
      )}

      {selectedLot && (
        <CreateTransportModal
          lot={selectedLot}
          onClose={() => setSelectedLot(null)}
          onSuccess={handleTransportCreated}
        />
      )}
    </AppLayout>
  );
}
