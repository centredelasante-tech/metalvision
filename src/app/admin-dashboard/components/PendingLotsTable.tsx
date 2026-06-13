'use client';
import React, { useState } from 'react';
import Link from 'next/link';

import MetalBadge from '@/components/ui/MetalBadge';
import Icon from '@/components/ui/AppIcon';

const PENDING_LOTS = [
  { id: 'lot-0848', client: 'Chantier Nord SARL', container: 'CT-001', metal: 'cuivre', priceEst: 281.96, confidence: 91, date: '04/06/2026 13:47', status: 'submitted' as const, urgent: false },
  { id: 'lot-0847', client: 'Démolition Rhône Est', container: 'CT-007', metal: 'fer', priceEst: 54.00, confidence: 87, date: '04/06/2026 11:22', status: 'submitted' as const, urgent: false },
  { id: 'lot-0846', client: 'Acier Industrie SA', container: 'CT-003', metal: 'acier', priceEst: 63.00, confidence: 78, date: '03/06/2026 16:05', status: 'submitted' as const, urgent: true },
  { id: 'lot-0845', client: 'BTP Provence SASU', container: 'CT-014', metal: 'aluminium', priceEst: 175.75, confidence: 93, date: '03/06/2026 09:14', status: 'submitted' as const, urgent: true },
  { id: 'lot-0844', client: 'Chantier Nord SARL', container: 'CT-001', metal: 'laiton', priceEst: 384.00, confidence: 96, date: '02/06/2026 14:30', status: 'submitted' as const, urgent: true },
  { id: 'lot-0843', client: 'Électricité Générale SAS', container: 'CT-009', metal: 'cuivre', priceEst: 127.40, confidence: 89, date: '02/06/2026 10:55', status: 'submitted' as const, urgent: true },
  { id: 'lot-0842', client: 'Métal & Co SARL', container: 'CT-002', metal: 'inox', priceEst: 134.00, confidence: 85, date: '01/06/2026 17:22', status: 'submitted' as const, urgent: true },
];

export default function PendingLotsTable() {
  const [selected, setSelected] = useState<string[]>([]);

  const toggleSelect = (id: string) => {
    setSelected((prev) =>
      prev.includes(id) ? prev.filter((x) => x !== id) : [...prev, id]
    );
  };

  const toggleAll = () => {
    setSelected(selected.length === PENDING_LOTS.length ? [] : PENDING_LOTS.map((l) => l.id));
  };

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="ClipboardDocumentListIcon" size={18} className="text-primary" />
          <h2 className="text-sm font-600 text-foreground">Lots en attente de traitement</h2>
          <span className="bg-red-100 text-red-600 text-xs font-700 px-2 py-0.5 rounded-full tabular-nums">
            {PENDING_LOTS.length}
          </span>
        </div>
        <Link
          href="/lot-management"
          className="text-xs text-primary font-600 hover:underline flex items-center gap-1"
        >
          Gestion complète
          <Icon name="ArrowRightIcon" size={12} />
        </Link>
      </div>

      {/* Bulk action bar */}
      {selected.length > 0 && (
        <div className="flex items-center gap-3 px-5 py-3 bg-primary/5 border-b border-primary/20 fade-in-up">
          <span className="text-sm font-600 text-primary">{selected.length} lot{selected.length > 1 ? 's' : ''} sélectionné{selected.length > 1 ? 's' : ''}</span>
          <div className="flex items-center gap-2 ml-auto">
            <button className="px-3 py-1.5 bg-primary text-primary-foreground rounded-lg text-xs font-600 btn-primary">
              Traiter en lot
            </button>
            <button
              onClick={() => setSelected([])}
              className="px-3 py-1.5 border border-border rounded-lg text-xs font-600 btn-ghost"
            >
              Annuler
            </button>
          </div>
        </div>
      )}

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border bg-muted/40">
              <th className="px-4 py-3 w-10">
                <input
                  type="checkbox"
                  checked={selected.length === PENDING_LOTS.length}
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
            {PENDING_LOTS.map((lot) => (
              <tr
                key={lot.id}
                className={`border-b border-border last:border-0 row-hover ${lot.urgent ? 'bg-amber-50/40' : ''}`}
              >
                <td className="px-4 py-3">
                  <input
                    type="checkbox"
                    checked={selected.includes(lot.id)}
                    onChange={() => toggleSelect(lot.id)}
                    className="rounded border-border accent-primary"
                  />
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-1.5">
                    {lot.urgent && (
                      <Icon name="ExclamationCircleIcon" size={14} className="text-amber-600 flex-shrink-0" />
                    )}
                    <span className="font-600 text-primary text-xs tabular-nums">#{lot.id.toUpperCase()}</span>
                  </div>
                </td>
                <td className="px-4 py-3 text-xs text-foreground font-500 whitespace-nowrap">{lot.client}</td>
                <td className="px-4 py-3">
                  <span className="text-xs font-500 bg-muted px-2 py-0.5 rounded">{lot.container}</span>
                </td>
                <td className="px-4 py-3">
                  <MetalBadge metal={lot.metal} />
                </td>
                <td className="px-4 py-3 tabular-nums font-600 text-foreground whitespace-nowrap">
                  {lot.priceEst.toFixed(2)} $CA
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-1.5">
                    <div className="w-12 h-1.5 bg-muted rounded-full overflow-hidden">
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
    </div>
  );
}