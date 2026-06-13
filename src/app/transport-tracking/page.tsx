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
  scheduled_time: string | null;
  transporter: string;
  external_reference: string | null;
  transport_status: 'pending' | 'assigned' | 'en_route' | 'picked_up' | 'delivered' | 'cancelled';
  notes: string | null;
  created_at: string;
  updated_at: string;
}

const STATUS_CONFIG: Record<string, { label: string; color: string; icon: string; step: number }> = {
  pending:   { label: 'En attente',    color: 'text-amber-600 bg-amber-50 border-amber-200',   icon: 'ClockIcon',           step: 0 },
  assigned:  { label: 'Assigné',       color: 'text-blue-600 bg-blue-50 border-blue-200',      icon: 'TruckIcon',           step: 1 },
  en_route:  { label: 'En route',      color: 'text-indigo-600 bg-indigo-50 border-indigo-200',icon: 'ArrowRightCircleIcon',step: 2 },
  picked_up: { label: 'Collecté',      color: 'text-purple-600 bg-purple-50 border-purple-200',icon: 'ArchiveBoxIcon',      step: 3 },
  delivered: { label: 'Livré',         color: 'text-green-600 bg-green-50 border-green-200',   icon: 'CheckCircleIcon',     step: 4 },
  cancelled: { label: 'Annulé',        color: 'text-red-600 bg-red-50 border-red-200',         icon: 'XCircleIcon',         step: -1 },
};

const STEPS = ['pending', 'assigned', 'en_route', 'picked_up', 'delivered'];

function TransportStatusBadge({ status }: { status: string }) {
  const cfg = STATUS_CONFIG[status] ?? STATUS_CONFIG.pending;
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-600 border ${cfg.color}`}>
      <Icon name={cfg.icon as Parameters<typeof Icon>[0]['name']} size={12} />
      {cfg.label}
    </span>
  );
}

function ProgressStepper({ status }: { status: string }) {
  const currentStep = STATUS_CONFIG[status]?.step ?? 0;
  const isCancelled = status === 'cancelled';

  return (
    <div className="flex items-center gap-0 w-full">
      {STEPS.map((s, i) => {
        const cfg = STATUS_CONFIG[s];
        const done = !isCancelled && currentStep >= cfg.step;
        const active = !isCancelled && currentStep === cfg.step;
        return (
          <React.Fragment key={s}>
            <div className="flex flex-col items-center gap-1 flex-shrink-0">
              <div
                className={`w-8 h-8 rounded-full flex items-center justify-center border-2 transition-all ${
                  done
                    ? 'bg-primary border-primary text-primary-foreground'
                    : active
                    ? 'bg-primary/10 border-primary text-primary' :'bg-muted border-border text-muted-foreground'
                }`}
              >
                <Icon name={cfg.icon as Parameters<typeof Icon>[0]['name']} size={14} />
              </div>
              <span className={`text-[10px] font-500 whitespace-nowrap ${done ? 'text-primary' : 'text-muted-foreground'}`}>
                {cfg.label}
              </span>
            </div>
            {i < STEPS.length - 1 && (
              <div className={`flex-1 h-0.5 mx-1 mb-4 rounded-full transition-all ${
                !isCancelled && currentStep > STATUS_CONFIG[STEPS[i]].step ? 'bg-primary' : 'bg-border'
              }`} />
            )}
          </React.Fragment>
        );
      })}
    </div>
  );
}

function TransportCard({ transport, onRefresh }: { transport: TransportRequest; onRefresh: () => void }) {
  const [polling, setPolling] = useState(false);

  const handlePollStatus = async () => {
    if (!transport.external_reference) return;
    setPolling(true);
    try {
      const res = await fetch('/api/transport/poll-status', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dry_run: false }),
      });
      if (res.ok) onRefresh();
    } finally {
      setPolling(false);
    }
  };

  return (
    <div className="bg-card border border-border rounded-xl overflow-hidden">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 px-5 py-4 border-b border-border">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-secondary flex items-center justify-center flex-shrink-0">
            <Icon name="TruckIcon" size={20} className="text-primary" />
          </div>
          <div>
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-sm font-700 text-foreground">Lot #{transport.lot_id.toUpperCase()}</span>
              {transport.container_id && (
                <span className="text-xs bg-muted px-2 py-0.5 rounded font-500">{transport.container_id}</span>
              )}
              <TransportStatusBadge status={transport.transport_status} />
            </div>
            <p className="text-xs text-muted-foreground mt-0.5">{transport.transporter}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {transport.external_reference && (
            <span className="text-xs font-600 text-muted-foreground tabular-nums bg-muted px-2 py-1 rounded">
              Réf: {transport.external_reference}
            </span>
          )}
          <button
            onClick={handlePollStatus}
            disabled={polling}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-600 border border-border rounded-lg btn-ghost disabled:opacity-50"
          >
            <Icon name="ArrowPathIcon" size={12} className={polling ? 'animate-spin' : ''} />
            Actualiser
          </button>
        </div>
      </div>

      {/* Progress stepper */}
      <div className="px-5 py-5 border-b border-border">
        <ProgressStepper status={transport.transport_status} />
      </div>

      {/* Details */}
      <div className="px-5 py-4 grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="space-y-3">
          <div>
            <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-1">Adresse de collecte</p>
            <div className="flex items-start gap-2">
              <Icon name="MapPinIcon" size={14} className="text-primary mt-0.5 flex-shrink-0" />
              <p className="text-sm text-foreground">{transport.pickup_address}</p>
            </div>
          </div>
          <div>
            <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-1">Adresse de livraison</p>
            <div className="flex items-start gap-2">
              <Icon name="FlagIcon" size={14} className="text-accent mt-0.5 flex-shrink-0" />
              <p className="text-sm text-foreground">{transport.dropoff_address}</p>
            </div>
          </div>
        </div>

        <div className="space-y-3">
          {transport.scheduled_time && (
            <div>
              <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-1">Heure prévue</p>
              <div className="flex items-center gap-2">
                <Icon name="CalendarIcon" size={14} className="text-primary flex-shrink-0" />
                <p className="text-sm font-600 text-foreground tabular-nums">
                  {new Date(transport.scheduled_time).toLocaleString('fr-CA', {
                    dateStyle: 'medium',
                    timeStyle: 'short',
                  })}
                </p>
              </div>
            </div>
          )}
          <div>
            <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-1">Créé le</p>
            <div className="flex items-center gap-2">
              <Icon name="ClockIcon" size={14} className="text-muted-foreground flex-shrink-0" />
              <p className="text-sm text-muted-foreground tabular-nums">
                {new Date(transport.created_at).toLocaleString('fr-CA', {
                  dateStyle: 'medium',
                  timeStyle: 'short',
                })}
              </p>
            </div>
          </div>
          {transport.notes && (
            <div>
              <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-1">Notes</p>
              <p className="text-sm text-foreground">{transport.notes}</p>
            </div>
          )}
        </div>
      </div>

      {/* Map placeholder */}
      <div className="mx-5 mb-5 rounded-xl bg-muted border border-border overflow-hidden h-32 flex items-center justify-center">
        <div className="flex flex-col items-center gap-2 text-muted-foreground">
          <Icon name="MapIcon" size={24} />
          <p className="text-xs font-500">Carte de suivi — intégration cartographique à venir</p>
        </div>
      </div>
    </div>
  );
}

export default function TransportTrackingPage() {
  const [transports, setTransports] = useState<TransportRequest[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const supabase = createClient();

  const fetchTransports = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: fetchError } = await supabase
        .from('transport_requests')
        .select('*')
        .order('created_at', { ascending: false });

      if (fetchError) {
        setError(fetchError.message);
      } else {
        setTransports(data ?? []);
      }
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchTransports();

    // Real-time subscription
    const channel = supabase
      .channel('transport_tracking')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'transport_requests' }, () => {
        fetchTransports();
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [fetchTransports]);

  const activeTransports = transports.filter(
    (t) => !['delivered', 'cancelled'].includes(t.transport_status)
  );
  const completedTransports = transports.filter(
    (t) => ['delivered', 'cancelled'].includes(t.transport_status)
  );

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-4xl mx-auto px-4 sm:px-6 py-8">
        {/* Page header */}
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-primary flex items-center justify-center">
              <Icon name="TruckIcon" size={20} className="text-primary-foreground" />
            </div>
            <div>
              <h1 className="text-xl font-700 text-foreground">Suivi du transport</h1>
              <p className="text-sm text-muted-foreground">Groupe Robert — Statut en temps réel</p>
            </div>
          </div>
          <button
            onClick={fetchTransports}
            className="flex items-center gap-2 px-4 py-2 text-sm font-600 border border-border rounded-lg btn-ghost"
          >
            <Icon name="ArrowPathIcon" size={14} className={loading ? 'animate-spin' : ''} />
            Actualiser
          </button>
        </div>

        {/* KPI row */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
          {[
            { label: 'En cours', count: activeTransports.length, color: 'text-blue-600', bg: 'bg-blue-50' },
            { label: 'Livrés', count: transports.filter(t => t.transport_status === 'delivered').length, color: 'text-green-600', bg: 'bg-green-50' },
            { label: 'En route', count: transports.filter(t => t.transport_status === 'en_route').length, color: 'text-indigo-600', bg: 'bg-indigo-50' },
            { label: 'Annulés', count: transports.filter(t => t.transport_status === 'cancelled').length, color: 'text-red-600', bg: 'bg-red-50' },
          ].map((kpi) => (
            <div key={kpi.label} className="bg-card border border-border rounded-xl p-4">
              <p className="text-xs text-muted-foreground font-500 mb-1">{kpi.label}</p>
              <p className={`text-2xl font-700 tabular-nums ${kpi.color}`}>{kpi.count}</p>
            </div>
          ))}
        </div>

        {/* Error */}
        {error && (
          <div className="flex items-center gap-2 p-4 bg-red-50 border border-red-200 rounded-xl mb-4">
            <Icon name="ExclamationCircleIcon" size={16} className="text-red-600" />
            <p className="text-sm text-red-700">{error}</p>
          </div>
        )}

        {/* Loading */}
        {loading && (
          <div className="space-y-4">
            {[1, 2].map((i) => (
              <div key={i} className="bg-card border border-border rounded-xl h-64 animate-pulse" />
            ))}
          </div>
        )}

        {/* Active transports */}
        {!loading && activeTransports.length > 0 && (
          <div className="space-y-4 mb-6">
            <h2 className="text-sm font-600 text-muted-foreground uppercase tracking-wide">
              Transports actifs ({activeTransports.length})
            </h2>
            {activeTransports.map((t) => (
              <TransportCard key={t.id} transport={t} onRefresh={fetchTransports} />
            ))}
          </div>
        )}

        {/* Completed transports */}
        {!loading && completedTransports.length > 0 && (
          <div className="space-y-4">
            <h2 className="text-sm font-600 text-muted-foreground uppercase tracking-wide">
              Historique ({completedTransports.length})
            </h2>
            {completedTransports.map((t) => (
              <TransportCard key={t.id} transport={t} onRefresh={fetchTransports} />
            ))}
          </div>
        )}

        {/* Empty state */}
        {!loading && transports.length === 0 && !error && (
          <div className="flex flex-col items-center justify-center py-20 text-center">
            <div className="w-16 h-16 rounded-2xl bg-muted flex items-center justify-center mb-4">
              <Icon name="TruckIcon" size={28} className="text-muted-foreground" />
            </div>
            <h3 className="text-base font-600 text-foreground mb-1">Aucun transport</h3>
            <p className="text-sm text-muted-foreground max-w-xs">
              Les demandes de transport apparaîtront ici une fois qu'un lot sera accepté.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
