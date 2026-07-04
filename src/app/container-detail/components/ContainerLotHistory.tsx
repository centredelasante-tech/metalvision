'use client';
import React, { useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import StatusBadge from '@/components/ui/StatusBadge';
import MetalBadge from '@/components/ui/MetalBadge';
import Icon from '@/components/ui/AppIcon';

interface Lot {
  id: string;
  metal: string;
  volumeEst: number;
  priceEst: number | null;
  priceFinal: number | null;
  status: 'submitted' | 'processed' | 'invoiced';
  date: string;
  confidence: number;
}

interface ContainerLotHistoryProps {
  containerId: string;
}

export default function ContainerLotHistory({ containerId }: ContainerLotHistoryProps) {
  const [lots, setLots] = useState<Lot[]>([]);
  const [loading, setLoading] = useState(true);
  const [sortCol, setSortCol] = useState<'date' | 'priceEst' | 'priceFinal'>('date');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  useEffect(() => {
    if (!containerId) return;
    const supabase = createClient();

    const fetchLots = async () => {
      setLoading(true);
      const { data, error } = await supabase
        .from('raw_measurements')
        .select('id, metal_type_predicted, volume_estimated_m3, metal_price_per_kg, price_paid, confidence, status, created_at')
        .eq('container_id', containerId)
        .order('created_at', { ascending: false });

      if (!error && data) {
        const mapped: Lot[] = data.map((row) => {
          const vol = Number(row.volume_estimated_m3 ?? 0);
          const pricePerKg = Number(row.metal_price_per_kg ?? 0);
          // Rough estimated price: volume * 1000 kg/m³ avg * price_per_kg (or null if no price data)
          const priceEst = pricePerKg > 0 ? parseFloat((vol * 1000 * pricePerKg).toFixed(2)) : null;
          const priceFinal = row.price_paid != null ? Number(row.price_paid) : null;
          const dateObj = new Date(row.created_at);
          const date = `${String(dateObj.getDate()).padStart(2, '0')}/${String(dateObj.getMonth() + 1).padStart(2, '0')}/${dateObj.getFullYear()}`;
          const rawStatus = row.status as string;
          const status: Lot['status'] =
            rawStatus === 'invoiced' ? 'invoiced' : rawStatus === 'processed' ? 'processed' : 'submitted';

          return {
            id: row.id,
            metal: row.metal_type_predicted ?? 'inconnu',
            volumeEst: vol,
            priceEst,
            priceFinal,
            status,
            date,
            confidence: Number(row.confidence ?? 0),
          };
        });
        setLots(mapped);
      }
      setLoading(false);
    };

    fetchLots();
  }, [containerId]);

  const handleSort = (col: typeof sortCol) => {
    if (sortCol === col) {
      setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    } else {
      setSortCol(col);
      setSortDir('desc');
    }
  };

  const sorted = [...lots].sort((a, b) => {
    let av: number | string = 0;
    let bv: number | string = 0;
    if (sortCol === 'date') { av = a.date; bv = b.date; }
    if (sortCol === 'priceEst') { av = a.priceEst ?? -1; bv = b.priceEst ?? -1; }
    if (sortCol === 'priceFinal') { av = a.priceFinal ?? -1; bv = b.priceFinal ?? -1; }
    if (av < bv) return sortDir === 'asc' ? -1 : 1;
    if (av > bv) return sortDir === 'asc' ? 1 : -1;
    return 0;
  });

  const totalFacture = lots.filter((l) => l.priceFinal != null).reduce((s, l) => s + (l.priceFinal ?? 0), 0);

  const SortIcon = ({ col }: { col: typeof sortCol }) => (
    <Icon
      name={sortCol === col ? (sortDir === 'asc' ? 'ChevronUpIcon' : 'ChevronDownIcon') : 'ChevronUpDownIcon'}
      size={12}
      className={sortCol === col ? 'text-primary' : 'text-muted-foreground'}
    />
  );

  if (loading) {
    return (
      <div className="bg-card rounded-xl border border-border p-6 space-y-3">
        {[1, 2, 3].map((i) => (
          <div key={i} className="h-10 bg-muted rounded-lg animate-pulse" />
        ))}
      </div>
    );
  }

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="ClipboardDocumentListIcon" size={16} className="text-muted-foreground" />
          <h3 className="text-sm font-600 text-foreground">Historique des lots</h3>
          <span className="text-xs bg-muted text-muted-foreground px-2 py-0.5 rounded-full tabular-nums">
            {lots.length} lots
          </span>
        </div>
        {totalFacture > 0 && (
          <div className="flex items-center gap-2">
            <span className="text-xs text-muted-foreground">
              Total facturé :{' '}
              <span className="font-700 text-foreground tabular-nums">
                {totalFacture.toFixed(2)} $CA
              </span>
            </span>
          </div>
        )}
      </div>

      {lots.length === 0 ? (
        <div className="py-10 text-center text-sm text-muted-foreground">
          Aucun lot enregistré pour ce conteneur
        </div>
      ) : (
        <>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border bg-muted/30">
                  <th className="px-4 py-3 text-left text-[11px] font-600 text-muted-foreground uppercase tracking-wide">Lot ID</th>
                  <th className="px-4 py-3 text-left text-[11px] font-600 text-muted-foreground uppercase tracking-wide">Métal</th>
                  <th className="px-4 py-3 text-left text-[11px] font-600 text-muted-foreground uppercase tracking-wide">Volume</th>
                  <th
                    className="px-4 py-3 text-left text-[11px] font-600 text-muted-foreground uppercase tracking-wide cursor-pointer hover:text-foreground"
                    onClick={() => handleSort('priceEst')}
                  >
                    <span className="flex items-center gap-1">Prix estimé <SortIcon col="priceEst" /></span>
                  </th>
                  <th
                    className="px-4 py-3 text-left text-[11px] font-600 text-muted-foreground uppercase tracking-wide cursor-pointer hover:text-foreground"
                    onClick={() => handleSort('priceFinal')}
                  >
                    <span className="flex items-center gap-1">Prix final <SortIcon col="priceFinal" /></span>
                  </th>
                  <th className="px-4 py-3 text-left text-[11px] font-600 text-muted-foreground uppercase tracking-wide">Confiance</th>
                  <th
                    className="px-4 py-3 text-left text-[11px] font-600 text-muted-foreground uppercase tracking-wide cursor-pointer hover:text-foreground"
                    onClick={() => handleSort('date')}
                  >
                    <span className="flex items-center gap-1">Date <SortIcon col="date" /></span>
                  </th>
                  <th className="px-4 py-3 text-left text-[11px] font-600 text-muted-foreground uppercase tracking-wide">Statut</th>
                </tr>
              </thead>
              <tbody>
                {sorted.map((lot) => (
                  <tr key={lot.id} className="border-b border-border last:border-0 row-hover">
                    <td className="px-4 py-3">
                      <span className="text-xs font-700 text-primary tabular-nums font-mono">
                        {lot.id.slice(0, 8).toUpperCase()}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      <MetalBadge metal={lot.metal} />
                    </td>
                    <td className="px-4 py-3 text-xs tabular-nums text-foreground">{lot.volumeEst.toFixed(2)} m³</td>
                    <td className="px-4 py-3 text-xs tabular-nums text-muted-foreground">
                      {lot.priceEst != null ? `${lot.priceEst.toFixed(2)} $CA` : '—'}
                    </td>
                    <td className="px-4 py-3">
                      {lot.priceFinal != null ? (
                        <div className="flex items-center gap-1.5">
                          <span className="text-xs tabular-nums font-600 text-foreground">{lot.priceFinal.toFixed(2)} $CA</span>
                          {lot.priceEst != null && (
                            <span className={`text-[10px] tabular-nums ${lot.priceFinal > lot.priceEst ? 'text-green-600' : 'text-red-500'}`}>
                              ({lot.priceFinal > lot.priceEst ? '+' : ''}{(lot.priceFinal - lot.priceEst).toFixed(2)})
                            </span>
                          )}
                        </div>
                      ) : (
                        <span className="text-xs text-muted-foreground">—</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-1.5">
                        <div className="w-10 h-1.5 bg-muted rounded-full overflow-hidden">
                          <div
                            className={`h-full rounded-full ${lot.confidence >= 90 ? 'bg-primary' : lot.confidence >= 75 ? 'bg-accent' : 'bg-red-500'}`}
                            style={{ width: `${lot.confidence}%` }}
                          />
                        </div>
                        <span className="text-xs tabular-nums text-muted-foreground">{lot.confidence}%</span>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-xs text-muted-foreground tabular-nums whitespace-nowrap">{lot.date}</td>
                    <td className="px-4 py-3">
                      <StatusBadge status={lot.status} size="sm" />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="flex items-center justify-between px-5 py-3 border-t border-border">
            <span className="text-xs text-muted-foreground">{lots.length} lots au total pour ce conteneur</span>
            <div className="flex items-center gap-1">
              <button className="w-8 h-8 rounded-lg border border-border btn-ghost flex items-center justify-center" disabled>
                <Icon name="ChevronLeftIcon" size={14} className="text-muted-foreground" />
              </button>
              <span className="text-xs text-muted-foreground px-2">Page 1 / 1</span>
              <button className="w-8 h-8 rounded-lg border border-border btn-ghost flex items-center justify-center" disabled>
                <Icon name="ChevronRightIcon" size={14} className="text-muted-foreground" />
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}