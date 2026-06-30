'use client';
import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import StatusBadge from '@/components/ui/StatusBadge';
import MetalBadge from '@/components/ui/MetalBadge';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';

type LotStatus = 'submitted' | 'processed' | 'invoiced';

interface RawLot {
  id: string;
  metal_type_predicted: string | null;
  official_weight_kg: number | null;
  volume_estimated_m3: number | null;
  price_paid: number | null;
  confidence: number | null;
  status: LotStatus;
  created_at: string;
  container_id: string | null;
  container_name?: string | null;
}

const PAGE_SIZE = 5;

function formatDate(iso: string): string {
  const d = new Date(iso);
  const day = String(d.getDate()).padStart(2, '0');
  const month = String(d.getMonth() + 1).padStart(2, '0');
  const year = d.getFullYear();
  return `${day}/${month}/${year}`;
}

function confidencePct(raw: number | null): number | null {
  if (raw === null) return null;
  // If stored as decimal (0–1), convert to percentage; otherwise use as-is
  return raw <= 1 ? Math.round(raw * 100) : Math.round(raw);
}

function ConfidenceBar({ value }: { value: number | null }) {
  if (value === null) return <span className="text-xs text-muted-foreground">—</span>;
  return (
    <div className="flex items-center gap-2">
      <div className="w-16 h-1.5 bg-muted rounded-full overflow-hidden">
        <div
          className={`h-full rounded-full ${value >= 90 ? 'bg-primary' : value >= 75 ? 'bg-accent' : 'bg-red-500'}`}
          style={{ width: `${value}%` }}
        />
      </div>
      <span className="text-xs tabular-nums text-muted-foreground">{value}%</span>
    </div>
  );
}

function PriceCell({ price_paid, volume_estimated_m3 }: { price_paid: number | null; volume_estimated_m3: number | null }) {
  if (price_paid !== null) {
    return <span className="tabular-nums font-600 text-foreground">{price_paid.toFixed(2)} $CA</span>;
  }
  if (volume_estimated_m3 !== null) {
    return (
      <span className="tabular-nums text-muted-foreground">
        {volume_estimated_m3.toFixed(2)} m³{' '}
        <span className="text-[10px] bg-muted px-1 py-0.5 rounded font-500 text-muted-foreground">estimation</span>
      </span>
    );
  }
  return <span className="text-xs text-muted-foreground">—</span>;
}

export default function RecentLotsTable() {
  const [lots, setLots] = useState<RawLot[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<'all' | LotStatus>('all');
  const [page, setPage] = useState(0);
  const [actionOpen, setActionOpen] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();

    supabase
      .from('raw_measurements')
      .select('id, metal_type_predicted, official_weight_kg, volume_estimated_m3, price_paid, confidence, status, created_at, container_id')
      .order('created_at', { ascending: false })
      .then(async ({ data, error: err }) => {
        if (err) {
          setError('Impossible de charger les lots. Veuillez réessayer.');
          setLoading(false);
          return;
        }

        const rows = (data ?? []) as RawLot[];

        // Collect unique container_ids to resolve names
        const containerIds = [...new Set(rows.map((r) => r.container_id).filter(Boolean))] as string[];

        let containerMap: Record<string, string> = {};
        if (containerIds.length > 0) {
          const { data: containers } = await supabase
            .from('containers')
            .select('id, name')
            .in('id', containerIds);
          if (containers) {
            containerMap = Object.fromEntries(containers.map((c: { id: string; name: string }) => [c.id, c.name]));
          }
        }

        const enriched = rows.map((r) => ({
          ...r,
          container_name: r.container_id ? (containerMap[r.container_id] ?? null) : null,
        }));

        setLots(enriched);
        setLoading(false);
      });
  }, []);

  const filtered = filter === 'all' ? lots : lots.filter((l) => l.status === filter);
  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
  const paginated = filtered.slice(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE);

  const handleFilterChange = (f: typeof filter) => {
    setFilter(f);
    setPage(0);
  };

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 px-4 py-4 border-b border-border">
        <h2 className="text-base font-600 text-foreground">Lots récents</h2>
        <div className="flex items-center gap-1 bg-muted rounded-lg p-1 overflow-x-auto">
          {(['all', 'submitted', 'processed', 'invoiced'] as const).map((f) => (
            <button
              key={`filter-${f}`}
              onClick={() => handleFilterChange(f)}
              className={`px-3 py-1.5 rounded-md text-xs font-600 transition-all whitespace-nowrap min-h-[32px] ${
                filter === f
                  ? 'bg-card text-foreground shadow-card'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              {f === 'all' ? 'Tous' : f === 'submitted' ? 'Soumis' : f === 'processed' ? 'Traités' : 'Facturés'}
            </button>
          ))}
        </div>
      </div>

      {/* Loading skeleton */}
      {loading && (
        <div className="divide-y divide-border">
          {[...Array(PAGE_SIZE)].map((_, i) => (
            <div key={i} className="flex items-center gap-3 px-4 py-3.5">
              <div className="h-3 bg-muted rounded animate-pulse w-24" />
              <div className="h-3 bg-muted rounded animate-pulse w-16" />
              <div className="h-3 bg-muted rounded animate-pulse w-20 ml-auto" />
            </div>
          ))}
        </div>
      )}

      {/* Error state */}
      {!loading && error && (
        <div className="px-5 py-10 text-center">
          <Icon name="ExclamationCircleIcon" size={24} className="text-red-400 mx-auto mb-2" />
          <p className="text-sm text-red-500">{error}</p>
        </div>
      )}

      {/* Empty state */}
      {!loading && !error && filtered.length === 0 && (
        <div className="px-5 py-10 text-center">
          <Icon name="InboxIcon" size={24} className="text-muted-foreground mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">
            {lots.length === 0 ? 'Aucun lot pour le moment.' : 'Aucun lot dans cette catégorie.'}
          </p>
        </div>
      )}

      {/* Mobile cards */}
      {!loading && !error && paginated.length > 0 && (
        <div className="md:hidden divide-y divide-border">
          {paginated.map((lot) => {
            const conf = confidencePct(lot.confidence);
            return (
              <div key={lot.id} className="p-4 relative">
                <div className="flex items-start justify-between gap-2">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-600 text-primary text-sm tabular-nums">#{lot.id.slice(0, 8).toUpperCase()}</span>
                      {lot.metal_type_predicted && <MetalBadge metal={lot.metal_type_predicted} />}
                      <StatusBadge status={lot.status} size="sm" />
                    </div>
                    <div className="flex items-center gap-3 mt-2 text-sm text-muted-foreground flex-wrap">
                      <span className="bg-muted px-2 py-0.5 rounded text-xs font-500">
                        {lot.container_name ?? '—'}
                      </span>
                      {lot.volume_estimated_m3 !== null && (
                        <span className="tabular-nums">{lot.volume_estimated_m3.toFixed(2)} m³</span>
                      )}
                      <PriceCell price_paid={lot.price_paid} volume_estimated_m3={lot.volume_estimated_m3} />
                    </div>
                    <div className="flex items-center gap-2 mt-2">
                      <ConfidenceBar value={conf} />
                      {conf !== null && <span className="text-xs tabular-nums text-muted-foreground">IA</span>}
                      <span className="text-xs text-muted-foreground ml-auto">{formatDate(lot.created_at)}</span>
                    </div>
                  </div>
                  {/* Action menu */}
                  <div className="relative flex-shrink-0">
                    <button
                      onClick={() => setActionOpen(actionOpen === lot.id ? null : lot.id)}
                      className="w-9 h-9 flex items-center justify-center rounded-lg btn-ghost text-muted-foreground"
                      aria-label="Actions"
                    >
                      <Icon name="EllipsisVerticalIcon" size={18} />
                    </button>
                    {actionOpen === lot.id && (
                      <div className="absolute right-0 top-10 w-40 bg-card border border-border rounded-xl shadow-modal z-20 overflow-hidden">
                        <Link
                          href="/lot-management"
                          className="flex items-center gap-2 px-4 py-3 text-sm text-foreground row-hover"
                          onClick={() => setActionOpen(null)}
                        >
                          <Icon name="EyeIcon" size={14} />
                          Voir le lot
                        </Link>
                        <button
                          className="flex items-center gap-2 px-4 py-3 text-sm text-foreground row-hover w-full text-left"
                          onClick={() => setActionOpen(null)}
                        >
                          <Icon name="DocumentTextIcon" size={14} />
                          Facture
                        </button>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Desktop table */}
      {!loading && !error && paginated.length > 0 && (
        <div className="hidden md:block overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border">
                {['Lot ID', 'Conteneur', 'Métal', 'Volume est.', 'Prix / Valeur', 'Confiance IA', 'Date', 'Statut'].map((h) => (
                  <th key={`th-${h}`} className="px-4 py-3 text-left text-[12px] font-600 text-muted-foreground uppercase tracking-wide whitespace-nowrap">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {paginated.map((lot) => {
                const conf = confidencePct(lot.confidence);
                return (
                  <tr key={lot.id} className="border-b border-border last:border-0 row-hover">
                    <td className="px-4 py-3">
                      <span className="font-600 text-primary text-xs tabular-nums">#{lot.id.slice(0, 8).toUpperCase()}</span>
                    </td>
                    <td className="px-4 py-3">
                      <span className="text-xs font-500 bg-muted px-2 py-0.5 rounded">
                        {lot.container_name ?? '—'}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      {lot.metal_type_predicted ? <MetalBadge metal={lot.metal_type_predicted} /> : <span className="text-xs text-muted-foreground">—</span>}
                    </td>
                    <td className="px-4 py-3 tabular-nums text-foreground">
                      {lot.volume_estimated_m3 !== null ? `${lot.volume_estimated_m3.toFixed(2)} m³` : '—'}
                    </td>
                    <td className="px-4 py-3">
                      <PriceCell price_paid={lot.price_paid} volume_estimated_m3={lot.volume_estimated_m3} />
                    </td>
                    <td className="px-4 py-3">
                      <ConfidenceBar value={conf} />
                    </td>
                    <td className="px-4 py-3 text-xs text-muted-foreground tabular-nums whitespace-nowrap">
                      {formatDate(lot.created_at)}
                    </td>
                    <td className="px-4 py-3"><StatusBadge status={lot.status} size="sm" /></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      <div className="flex items-center justify-between px-4 py-3 border-t border-border flex-wrap gap-2">
        <span className="text-xs text-muted-foreground">
          {loading ? '…' : `${filtered.length} lot${filtered.length > 1 ? 's' : ''} affichés`}
        </span>
        {!loading && totalPages > 1 && (
          <div className="flex items-center gap-2">
            <button
              onClick={() => setPage((p) => Math.max(0, p - 1))}
              disabled={page === 0}
              className="w-8 h-8 flex items-center justify-center rounded-lg btn-ghost text-muted-foreground disabled:opacity-40"
            >
              <Icon name="ChevronLeftIcon" size={16} />
            </button>
            <span className="text-xs text-muted-foreground tabular-nums">{page + 1}/{totalPages}</span>
            <button
              onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
              disabled={page >= totalPages - 1}
              className="w-8 h-8 flex items-center justify-center rounded-lg btn-ghost text-muted-foreground disabled:opacity-40"
            >
              <Icon name="ChevronRightIcon" size={16} />
            </button>
          </div>
        )}
        <Link href="/lot-management" className="text-xs text-primary font-600 hover:underline flex items-center gap-1">
          Voir tout
          <Icon name="ArrowRightIcon" size={12} />
        </Link>
      </div>
    </div>
  );
}