'use client';
import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import MetalBadge from '@/components/ui/MetalBadge';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';

interface PendingLot {
  id: string;
  client: string;
  containerName: string | null;
  metal: string;
  priceEst: number | null;
  confidence: number | null;
  date: string;
}

const PAGE_SIZE = 5;

export default function PendingLotsTable() {
  const [lots, setLots] = useState<PendingLot[]>([]);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<string[]>([]);
  const [page, setPage] = useState(0);
  const [actionOpen, setActionOpen] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();

    const fetchLots = async () => {
      const { data, error } = await supabase
        .from('raw_measurements')
        .select(`
          id,
          metal_type_predicted,
          confidence,
          price_paid,
          created_at,
          companies ( name ),
          containers ( name )
        `)
        .eq('status', 'submitted')
        .order('created_at', { ascending: false })
        .limit(50);

      if (error || !data) {
        setLots([]);
        setLoading(false);
        return;
      }

      const mapped: PendingLot[] = data.map((row: any) => ({
        id: row.id,
        client: row.companies?.name ?? 'Client inconnu',
        containerName: row.containers?.name ?? null,
        metal: row.metal_type_predicted ?? 'inconnu',
        priceEst: row.price_paid != null ? Number(row.price_paid) : null,
        confidence: row.confidence != null ? Math.round(Number(row.confidence)) : null,
        date: row.created_at
          ? new Date(row.created_at).toLocaleString('fr-CA', {
              day: '2-digit',
              month: '2-digit',
              year: 'numeric',
              hour: '2-digit',
              minute: '2-digit',
            })
          : '—',
      }));

      setLots(mapped);
      setLoading(false);
    };

    fetchLots();
  }, []);

  const totalPages = Math.ceil(lots.length / PAGE_SIZE);
  const paginated = lots.slice(page * PAGE_SIZE, page * PAGE_SIZE + PAGE_SIZE);

  const toggleSelect = (id: string) => {
    setSelected((prev) => prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]);
  };
  const toggleAll = () => {
    setSelected(lots.length > 0 && selected.length === lots.length ? [] : lots.map((l) => l.id));
  };

  const shortId = (id: string) => id.slice(0, 8).toUpperCase();

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-4 py-4 border-b border-border">
        <div className="flex items-center gap-2 flex-wrap">
          <Icon name="ClipboardDocumentListIcon" size={18} className="text-primary" />
          <h2 className="text-base font-600 text-foreground">Lots en attente</h2>
          {!loading && (
            <span className={`text-xs font-700 px-2 py-0.5 rounded-full tabular-nums ${lots.length > 0 ? 'bg-red-100 text-red-600' : 'bg-muted text-muted-foreground'}`}>
              {lots.length}
            </span>
          )}
        </div>
        <Link href="/lot-management" className="text-xs text-primary font-600 hover:underline flex items-center gap-1">
          Tout voir
          <Icon name="ArrowRightIcon" size={12} />
        </Link>
      </div>

      {loading ? (
        <div className="p-4 space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={`lot-skel-${i}`} className="h-12 bg-muted rounded-lg animate-pulse" />
          ))}
        </div>
      ) : lots.length === 0 ? (
        <div className="py-12 text-center">
          <Icon name="ClipboardDocumentListIcon" size={32} className="text-muted-foreground mx-auto mb-3" />
          <p className="text-sm font-600 text-foreground">Aucun lot en attente</p>
          <p className="text-xs text-muted-foreground mt-1">Tous les lots ont été traités</p>
        </div>
      ) : (
        <>
          {/* Bulk action bar */}
          {selected.length > 0 && (
            <div className="flex items-center gap-3 px-4 py-3 bg-primary/5 border-b border-primary/20 fade-in-up flex-wrap">
              <span className="text-sm font-600 text-primary">{selected.length} sélectionné{selected.length > 1 ? 's' : ''}</span>
              <div className="flex items-center gap-2 ml-auto">
                <button className="px-3 py-2 bg-primary text-primary-foreground rounded-lg text-xs font-600 btn-primary min-h-[36px]">
                  Traiter en lot
                </button>
                <button onClick={() => setSelected([])} className="px-3 py-2 border border-border rounded-lg text-xs font-600 btn-ghost min-h-[36px]">
                  Annuler
                </button>
              </div>
            </div>
          )}

          {/* Mobile cards */}
          <div className="md:hidden divide-y divide-border">
            {paginated.map((lot) => (
              <div key={lot.id} className="p-4 relative">
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-center gap-2 flex-shrink-0 mt-0.5">
                    <input
                      type="checkbox"
                      checked={selected.includes(lot.id)}
                      onChange={() => toggleSelect(lot.id)}
                      className="rounded border-border accent-primary w-4 h-4"
                    />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <span className="font-600 text-primary text-sm tabular-nums">#{shortId(lot.id)}</span>
                      <MetalBadge metal={lot.metal} />
                    </div>
                    <p className="text-sm text-foreground font-500 mt-1 truncate">{lot.client}</p>
                    <div className="flex items-center gap-3 mt-1 flex-wrap">
                      {lot.containerName && (
                        <span className="text-xs bg-muted px-2 py-0.5 rounded font-500">{lot.containerName}</span>
                      )}
                      {lot.priceEst != null ? (
                        <span className="text-sm font-600 text-foreground tabular-nums">{lot.priceEst.toFixed(2)} $CA</span>
                      ) : (
                        <span className="text-xs text-muted-foreground">Prix non défini</span>
                      )}
                      {lot.confidence != null && (
                        <span className="text-xs text-muted-foreground tabular-nums">{lot.confidence}% IA</span>
                      )}
                    </div>
                    <p className="text-xs text-muted-foreground mt-1 tabular-nums">{lot.date}</p>
                  </div>
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
                          <Icon name="PencilSquareIcon" size={14} />
                          Traiter
                        </Link>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>

          {/* Desktop table */}
          <div className="hidden md:block overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border bg-muted/40">
                  <th className="px-4 py-3 w-10">
                    <input
                      type="checkbox"
                      checked={lots.length > 0 && selected.length === lots.length}
                      onChange={toggleAll}
                      className="rounded border-border accent-primary"
                    />
                  </th>
                  {['Lot ID', 'Client', 'Conteneur', 'Métal', 'Prix est.', 'Confiance', 'Soumis le', 'Action'].map((h) => (
                    <th key={`admin-th-${h}`} className="px-4 py-3 text-left text-[11px] font-600 text-muted-foreground uppercase tracking-wide whitespace-nowrap">
                      {h}
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {paginated.map((lot) => (
                  <tr key={lot.id} className="border-b border-border last:border-0 row-hover">
                    <td className="px-4 py-3">
                      <input
                        type="checkbox"
                        checked={selected.includes(lot.id)}
                        onChange={() => toggleSelect(lot.id)}
                        className="rounded border-border accent-primary"
                      />
                    </td>
                    <td className="px-4 py-3">
                      <span className="font-600 text-primary text-xs tabular-nums">#{shortId(lot.id)}</span>
                    </td>
                    <td className="px-4 py-3 text-xs text-foreground font-500 whitespace-nowrap">{lot.client}</td>
                    <td className="px-4 py-3">
                      {lot.containerName ? (
                        <span className="text-xs font-500 bg-muted px-2 py-0.5 rounded">{lot.containerName}</span>
                      ) : (
                        <span className="text-xs text-muted-foreground">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3"><MetalBadge metal={lot.metal} /></td>
                    <td className="px-4 py-3 tabular-nums font-600 text-foreground whitespace-nowrap">
                      {lot.priceEst != null ? `${lot.priceEst.toFixed(2)} $CA` : '—'}
                    </td>
                    <td className="px-4 py-3">
                      {lot.confidence != null ? (
                        <div className="flex items-center gap-1.5">
                          <div className="w-12 h-1.5 bg-muted rounded-full overflow-hidden">
                            <div
                              className={`h-full rounded-full ${lot.confidence >= 90 ? 'bg-primary' : lot.confidence >= 75 ? 'bg-accent' : 'bg-red-500'}`}
                              style={{ width: `${lot.confidence}%` }}
                            />
                          </div>
                          <span className="text-xs tabular-nums text-muted-foreground">{lot.confidence}%</span>
                        </div>
                      ) : (
                        <span className="text-xs text-muted-foreground">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3 text-xs text-muted-foreground tabular-nums whitespace-nowrap">{lot.date}</td>
                    <td className="px-4 py-3">
                      <Link
                        href="/lot-management"
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-primary text-primary-foreground rounded-lg text-xs font-600 btn-primary whitespace-nowrap"
                      >
                        <Icon name="PencilSquareIcon" size={12} className="text-primary-foreground" />
                        Traiter
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="flex items-center justify-center gap-3 px-4 py-3 border-t border-border">
              <button
                onClick={() => setPage((p) => Math.max(0, p - 1))}
                disabled={page === 0}
                className="w-9 h-9 flex items-center justify-center rounded-lg btn-ghost text-muted-foreground disabled:opacity-40"
              >
                <Icon name="ChevronLeftIcon" size={16} />
              </button>
              <span className="text-sm text-muted-foreground tabular-nums">{page + 1} / {totalPages}</span>
              <button
                onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))}
                disabled={page >= totalPages - 1}
                className="w-9 h-9 flex items-center justify-center rounded-lg btn-ghost text-muted-foreground disabled:opacity-40"
              >
                <Icon name="ChevronRightIcon" size={16} />
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}