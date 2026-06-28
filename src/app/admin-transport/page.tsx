'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';

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
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-border sticky top-0 bg-card z-10">
          <div className="flex items-center gap-3">
            <Icon name="TruckIcon" size={18} className="text-primary" />
            <h2 className="text-base font-700 text-foreground">Détail transport interne</h2>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg btn-ghost">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>

        <div className="p-5 space-y-4">
          {/* Provider badge */}
          <div className={`flex items-center gap-2 px-3 py-2 rounded-lg ${isInternal ? 'bg-secondary' : 'bg-muted'}`}>
            <Icon name="TruckIcon" size={14} className="text-primary" />
            <span className="text-xs font-600 text-primary">
              {isInternal ? 'Transport interne MetalVision' : 'Transport du client'}
            </span>
          </div>

          {/* Info grid */}
          <div className="grid grid-cols-2 gap-3">
            {[
              { label: 'Lot', value: `#${transport.lot_id.toUpperCase()}` },
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

          {/* Proof files */}
          {(transport.proof_photo_url || transport.proof_document_url) && (
            <div className="space-y-2">
              <p className="text-xs font-600 text-foreground">Preuves</p>
              <div className="flex flex-wrap gap-2">
                {transport.proof_photo_url && (
                  <a
                    href={transport.proof_photo_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-1.5 px-3 py-2 bg-muted rounded-lg text-xs font-600 text-foreground hover:bg-secondary transition-colors"
                  >
                    <Icon name="PhotoIcon" size={12} />
                    Photo de preuve
                  </a>
                )}
                {transport.proof_document_url && (
                  <a
                    href={transport.proof_document_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="flex items-center gap-1.5 px-3 py-2 bg-muted rounded-lg text-xs font-600 text-foreground hover:bg-secondary transition-colors"
                  >
                    <Icon name="DocumentTextIcon" size={12} />
                    Document
                  </a>
                )}
              </div>
            </div>
          )}

          {/* Manual status update */}
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

export default function AdminTransportPage() {
  const [transports, setTransports] = useState<TransportRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState('all');
  const [providerFilter, setProviderFilter] = useState('all');
  const [selectedTransport, setSelectedTransport] = useState<TransportRequest | null>(null);
  const supabase = createClient();

  const fetchTransports = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      let query = supabase
        .from('transport_requests')
        .select('*')
        .order('created_at', { ascending: false });

      if (statusFilter !== 'all') {
        query = query.eq('transport_status', statusFilter);
      }
      if (providerFilter !== 'all') {
        query = query.eq('provider', providerFilter);
      }

      const { data, error: fetchError } = await query;
      if (fetchError) setError(fetchError.message);
      else setTransports(data ?? []);
    } finally {
      setLoading(false);
    }
  }, [statusFilter, providerFilter, supabase]);

  useEffect(() => {
    fetchTransports();

    const channel = supabase
      .channel('admin_transport')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'transport_requests' }, () => {
        fetchTransports();
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [fetchTransports, supabase]);

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

  const kpis = {
    total: transports.length,
    active: transports.filter(t => !['delivered', 'cancelled'].includes(t.transport_status)).length,
    delivered: transports.filter(t => t.transport_status === 'delivered').length,
    internal: transports.filter(t => t.provider === 'internal').length,
  };

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-6xl mx-auto px-4 sm:px-6 py-8">
        {/* Header */}
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 mb-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-primary flex items-center justify-center">
              <Icon name="TruckIcon" size={20} className="text-primary-foreground" />
            </div>
            <div>
              <h1 className="text-xl font-700 text-foreground">Transports internes</h1>
              <p className="text-sm text-muted-foreground">MetalVision — Gestion de la flotte interne</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-xs font-600 text-green-700 bg-green-50 border border-green-200 px-3 py-1.5 rounded-lg flex items-center gap-1.5">
              <Icon name="CheckCircleIcon" size={12} />
              Mode transport interne actif
            </span>
          </div>
        </div>

        {/* KPI cards */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
          {[
            { label: 'Total', value: kpis.total, color: 'text-foreground' },
            { label: 'En cours', value: kpis.active, color: 'text-blue-600' },
            { label: 'Livrés', value: kpis.delivered, color: 'text-green-600' },
            { label: 'Internes', value: kpis.internal, color: 'text-primary' },
          ].map((kpi) => (
            <div key={kpi.label} className="bg-card border border-border rounded-xl p-4">
              <p className="text-xs text-muted-foreground font-500 mb-1">{kpi.label}</p>
              <p className={`text-2xl font-700 tabular-nums ${kpi.color}`}>{kpi.value}</p>
            </div>
          ))}
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
            { value: 'internal', label: 'Interne MetalVision' },
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

        {/* Error */}
        {error && (
          <div className="flex items-center gap-2 p-4 bg-red-50 border border-red-200 rounded-xl mb-4">
            <Icon name="ExclamationCircleIcon" size={16} className="text-red-600" />
            <p className="text-sm text-red-700">{error}</p>
          </div>
        )}

        {/* Table */}
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
                {loading ? (
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
                        <span className="font-600 text-primary text-xs tabular-nums">#{t.lot_id.toUpperCase()}</span>
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
      </div>

      {/* Detail modal */}
      {selectedTransport && (
        <DetailModal
          transport={selectedTransport}
          onClose={() => setSelectedTransport(null)}
          onStatusUpdate={handleStatusUpdate}
        />
      )}
    </div>
  );
}
