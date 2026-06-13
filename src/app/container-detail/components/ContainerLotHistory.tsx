'use client';
import React, { useState } from 'react';
import StatusBadge from '@/components/ui/StatusBadge';
import MetalBadge from '@/components/ui/MetalBadge';
import Icon from '@/components/ui/AppIcon';

const CONTAINER_LOTS = [
  { id: 'lot-0846', client: 'Acier Industrie SA', metal: 'acier', volumeEst: 2.10, priceEst: 63.00, priceFinal: null, status: 'submitted' as const, date: '03/06/2026', confidence: 78 },
  { id: 'lot-0839', client: 'Acier Industrie SA', metal: 'fer', volumeEst: 1.50, priceEst: 45.00, priceFinal: 52.20, status: 'invoiced' as const, date: '18/05/2026', confidence: 91 },
  { id: 'lot-0831', client: 'Acier Industrie SA', metal: 'acier', volumeEst: 3.20, priceEst: 96.00, priceFinal: 88.80, status: 'invoiced' as const, date: '02/05/2026', confidence: 85 },
  { id: 'lot-0822', client: 'Acier Industrie SA', metal: 'inox', volumeEst: 0.45, priceEst: 90.00, priceFinal: 97.20, status: 'invoiced' as const, date: '14/04/2026', confidence: 93 },
  { id: 'lot-0814', client: 'Acier Industrie SA', metal: 'fer', volumeEst: 2.80, priceEst: 84.00, priceFinal: 79.20, status: 'invoiced' as const, date: '28/03/2026', confidence: 88 },
  { id: 'lot-0807', client: 'Acier Industrie SA', metal: 'acier', volumeEst: 1.90, priceEst: 57.00, priceFinal: 62.40, status: 'invoiced' as const, date: '12/03/2026', confidence: 82 },
];

export default function ContainerLotHistory() {
  const [sortCol, setSortCol] = useState<'date' | 'priceEst' | 'priceFinal'>('date');
  const [sortDir, setSortDir] = useState<'asc' | 'desc'>('desc');

  const handleSort = (col: typeof sortCol) => {
    if (sortCol === col) {
      setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    } else {
      setSortCol(col);
      setSortDir('desc');
    }
  };

  const sorted = [...CONTAINER_LOTS].sort((a, b) => {
    let av: number | string = 0;
    let bv: number | string = 0;
    if (sortCol === 'date') { av = a.date; bv = b.date; }
    if (sortCol === 'priceEst') { av = a.priceEst; bv = b.priceEst; }
    if (sortCol === 'priceFinal') { av = a.priceFinal ?? -1; bv = b.priceFinal ?? -1; }
    if (av < bv) return sortDir === 'asc' ? -1 : 1;
    if (av > bv) return sortDir === 'asc' ? 1 : -1;
    return 0;
  });

  const SortIcon = ({ col }: { col: typeof sortCol }) => (
    <Icon
      name={sortCol === col ? (sortDir === 'asc' ? 'ChevronUpIcon' : 'ChevronDownIcon') : 'ChevronUpDownIcon'}
      size={12}
      className={sortCol === col ? 'text-primary' : 'text-muted-foreground'}
    />
  );

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="ClipboardDocumentListIcon" size={16} className="text-muted-foreground" />
          <h3 className="text-sm font-600 text-foreground">Historique des lots</h3>
          <span className="text-xs bg-muted text-muted-foreground px-2 py-0.5 rounded-full tabular-nums">
            {CONTAINER_LOTS.length} lots
          </span>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-xs text-muted-foreground">
            Total facturé :{' '}
            <span className="font-700 text-foreground tabular-nums">
              {CONTAINER_LOTS.filter((l) => l.priceFinal).reduce((s, l) => s + (l.priceFinal ?? 0), 0).toFixed(2)} $CA
            </span>
          </span>
        </div>
      </div>

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
                  <span className="text-xs font-700 text-primary tabular-nums">#{lot.id.toUpperCase()}</span>
                </td>
                <td className="px-4 py-3">
                  <MetalBadge metal={lot.metal} />
                </td>
                <td className="px-4 py-3 text-xs tabular-nums text-foreground">{lot.volumeEst.toFixed(2)} m³</td>
                <td className="px-4 py-3 text-xs tabular-nums text-muted-foreground">{lot.priceEst.toFixed(2)} $CA</td>
                <td className="px-4 py-3">
                  {lot.priceFinal !== null ? (
                    <div className="flex items-center gap-1.5">
                      <span className="text-xs tabular-nums font-600 text-foreground">{lot.priceFinal.toFixed(2)} $CA</span>
                      <span className={`text-[10px] tabular-nums ${lot.priceFinal > lot.priceEst ? 'text-green-600' : 'text-red-500'}`}>
                        ({lot.priceFinal > lot.priceEst ? '+' : ''}{(lot.priceFinal - lot.priceEst).toFixed(2)})
                      </span>
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
        <span className="text-xs text-muted-foreground">{CONTAINER_LOTS.length} lots au total pour ce conteneur</span>
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
    </div>
  );
}