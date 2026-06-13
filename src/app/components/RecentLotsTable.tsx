'use client';
import React, { useState } from 'react';
import Link from 'next/link';
import StatusBadge from '@/components/ui/StatusBadge';
import MetalBadge from '@/components/ui/MetalBadge';
import Icon from '@/components/ui/AppIcon';

const LOTS = [
  { id: 'lot-0847', container: 'CT-001', metal: 'cuivre', volumeEst: 0.42, priceEst: 187.60, status: 'processed' as const, date: '04/06/2026', confidence: 94 },
  { id: 'lot-0846', container: 'CT-003', metal: 'fer', volumeEst: 1.80, priceEst: 54.00, status: 'submitted' as const, date: '03/06/2026', confidence: 87 },
  { id: 'lot-0845', container: 'CT-001', metal: 'aluminium', volumeEst: 0.95, priceEst: 175.75, status: 'invoiced' as const, date: '02/06/2026', confidence: 91 },
  { id: 'lot-0844', container: 'CT-002', metal: 'acier', volumeEst: 2.10, priceEst: 63.00, status: 'submitted' as const, date: '01/06/2026', confidence: 78 },
  { id: 'lot-0843', container: 'CT-003', metal: 'laiton', volumeEst: 0.31, priceEst: 248.00, status: 'processed' as const, date: '31/05/2026', confidence: 96 },
  { id: 'lot-0842', container: 'CT-001', metal: 'inox', volumeEst: 0.67, priceEst: 134.00, status: 'invoiced' as const, date: '30/05/2026', confidence: 89 },
  { id: 'lot-0841', container: 'CT-004', metal: 'fer', volumeEst: 3.20, priceEst: 96.00, status: 'submitted' as const, date: '29/05/2026', confidence: 82 },
  { id: 'lot-0840', container: 'CT-002', metal: 'cuivre', volumeEst: 0.28, priceEst: 125.44, status: 'invoiced' as const, date: '28/05/2026', confidence: 93 },
];

export default function RecentLotsTable() {
  const [filter, setFilter] = useState<'all' | 'submitted' | 'processed' | 'invoiced'>('all');

  const filtered = filter === 'all' ? LOTS : LOTS.filter((l) => l.status === filter);

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 px-5 py-4 border-b border-border">
        <h2 className="text-sm font-600 text-foreground">Lots récents</h2>
        <div className="flex items-center gap-1 bg-muted rounded-lg p-1">
          {(['all', 'submitted', 'processed', 'invoiced'] as const).map((f) => (
            <button
              key={`filter-${f}`}
              onClick={() => setFilter(f)}
              className={`px-3 py-1 rounded-md text-xs font-600 transition-all ${
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

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border">
              {['Lot ID', 'Conteneur', 'Métal', 'Volume est.', 'Prix est.', 'Confiance IA', 'Date', 'Statut'].map((h) => (
                <th key={`th-${h}`} className="px-4 py-3 text-left text-[12px] font-600 text-muted-foreground uppercase tracking-wide whitespace-nowrap">
                  {h}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {filtered.map((lot) => (
              <tr key={lot.id} className="border-b border-border last:border-0 row-hover">
                <td className="px-4 py-3">
                  <span className="font-600 text-primary text-xs tabular-nums">#{lot.id.toUpperCase()}</span>
                </td>
                <td className="px-4 py-3">
                  <span className="text-xs font-500 bg-muted px-2 py-0.5 rounded">{lot.container}</span>
                </td>
                <td className="px-4 py-3">
                  <MetalBadge metal={lot.metal} />
                </td>
                <td className="px-4 py-3 tabular-nums text-foreground">{lot.volumeEst.toFixed(2)} m³</td>
                <td className="px-4 py-3 tabular-nums font-600 text-foreground">{lot.priceEst.toFixed(2)} $CA</td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <div className="w-16 h-1.5 bg-muted rounded-full overflow-hidden">
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

      {filtered.length === 0 && (
        <div className="py-10 text-center text-sm text-muted-foreground">
          Aucun lot dans cette catégorie
        </div>
      )}

      <div className="flex items-center justify-between px-5 py-3 border-t border-border">
        <span className="text-xs text-muted-foreground">{filtered.length} lot{filtered.length > 1 ? 's' : ''} affichés</span>
        <Link href="/lot-management" className="text-xs text-primary font-600 hover:underline flex items-center gap-1">
          Voir la gestion complète
          <Icon name="ArrowRightIcon" size={12} />
        </Link>
      </div>
    </div>
  );
}