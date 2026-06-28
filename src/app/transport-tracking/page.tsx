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

const STATUS_CONFIG: Record<string, { label: string; color: string; icon: string; step: number }> = {
  scheduled:  { label: 'Planifié',    color: 'text-amber-600 bg-amber-50 border-amber-200',    icon: 'ClockIcon',           step: 0 },
  in_transit: { label: 'En transit',  color: 'text-indigo-600 bg-indigo-50 border-indigo-200', icon: 'TruckIcon',           step: 1 },
  arrived:    { label: 'Arrivé',      color: 'text-purple-600 bg-purple-50 border-purple-200', icon: 'MapPinIcon',          step: 2 },
  delivered:  { label: 'Livré',       color: 'text-green-600 bg-green-50 border-green-200',    icon: 'CheckCircleIcon',     step: 3 },
  cancelled:  { label: 'Annulé',      color: 'text-red-600 bg-red-50 border-red-200',          icon: 'XCircleIcon',         step: -1 },
};

const STEPS = ['scheduled', 'in_transit', 'arrived', 'delivered'];

function TransportStatusBadge({ status }: { status: string }) {
  const cfg = STATUS_CONFIG[status] ?? STATUS_CONFIG.scheduled;
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
  const [refreshing, setRefreshing] = useState(false);

  const handleRefresh = async () => {
    setRefreshing(true);
    try {
      const res = await fetch(`/api/transport/${transport.id}/status`);
      if (res.ok) onRefresh();
    } finally {
      setRefreshing(false);
    }
  };

  const isInternal = transport.provider === 'internal';

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
            <div className="flex items-center gap-2 mt-0.5">
              <span className={`text-xs font-600 px-2 py-0.5 rounded-full ${isInternal ? 'text-primary bg-secondary' : 'text-muted-foreground bg-muted'}`}>
                {isInternal ? 'Transport interne METALTRACE' : 'Transport du client'}
              </span>
            </div>
          </div>
        </div>
        <button
          onClick={handleRefresh}
          disabled={refreshing}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-600 border border-border rounded-lg btn-ghost disabled:opacity-50"
        >
          <Icon name="ArrowPathIcon" size={12} className={refreshing ? 'animate-spin' : ''} />
          Actualiser
        </button>
      </div>

      {/* Progress stepper */}
      <div className="px-5 py-5 border-b border-border">
        <ProgressStepper status={transport.transport_status} />
      </div>

      {/* Details */}
      <div className="px-5 py-4 grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="space-y-3">
          {isInternal && transport.driver_name && (
            <div>
              <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-1">Chauffeur</p>
              <div className="flex items-center gap-2">
                <Icon name="UserIcon" size={14} className="text-primary flex-shrink-0" />
                <p className="text-sm font-600 text-foreground">{transport.driver_name}</p>
              </div>
            </div>
          )}
          {transport.truck_number && (
            <div>
              <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-1">Camion</p>
              <div className="flex items-center gap-2">
                <Icon name="TruckIcon" size={14} className="text-primary flex-shrink-0" />
                <p className="text-sm font-600 text-foreground">{transport.truck_number}</p>
              </div>
            </div>
          )}
          {transport.transport_mode && (
            <div>
              <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-1">Mode</p>
              <p className="text-sm text-foreground capitalize">{transport.transport_mode}</p>
            </div>
          )}
        </div>

        <div className="space-y-3">
          {(transport.arrival_eta || transport.scheduled_time) && (
            <div>
              <p className="text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-1">ETA d&apos;arrivée</p>
              <div className="flex items-center gap-2">
                <Icon name="CalendarIcon" size={14} className="text-primary flex-shrink-0" />
                <p className="text-sm font-600 text-foreground tabular-nums">
                  {new Date(transport.arrival_eta ?? transport.scheduled_time!).toLocaleString('fr-CA', {
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

      {/* Proof files */}
      {(transport.proof_photo_url || transport.proof_document_url) && (
        <div className="px-5 pb-4 flex flex-wrap gap-2">
          <p className="w-full text-[11px] font-600 text-muted-foreground uppercase tracking-wide mb-1">Preuves</p>
          {transport.proof_photo_url && (
            <a
              href={transport.proof_photo_url}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1.5 px-3 py-1.5 bg-muted rounded-lg text-xs font-600 text-foreground hover:bg-secondary transition-colors"
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
              className="flex items-center gap-1.5 px-3 py-1.5 bg-muted rounded-lg text-xs font-600 text-foreground hover:bg-secondary transition-colors"
            >
              <Icon name="DocumentTextIcon" size={12} />
              Document de preuve
            </a>
          )}
        </div>
      )}

      {/* Map placeholder */}
      <div className="mx-5 mb-5 rounded-xl bg-muted border border-border overflow-hidden h-32 flex items-center justify-center">
        <div className="flex flex-col items-center gap-2 text-muted-foreground">
          <Icon name="MapIcon" size={24} />
          <p className="text-xs font-500">Carte de suivi GPS — intégration à venir</p>
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
  }, [supabase]);

  useEffect(() => {
    fetchTransports();

    const channel = supabase
      .channel('transport_tracking')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'transport_requests' }, () => {
        fetchTransports();
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [fetchTransports, supabase]);

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
              <p className="text-sm text-muted-foreground">Transport interne METALTRACE — Statut en temps réel</p>
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
            { label: 'En cours', count: activeTransports.length, color: 'text-blue-600' },
            { label: 'Livrés', count: transports.filter(t => t.transport_status === 'delivered').length, color: 'text-green-600' },
            { label: 'En transit', count: transports.filter(t => t.transport_status === 'in_transit').length, color: 'text-indigo-600' },
            { label: 'Annulés', count: transports.filter(t => t.transport_status === 'cancelled').length, color: 'text-red-600' },
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
              Les demandes de transport apparaîtront ici une fois qu&apos;un lot sera soumis.
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
