'use client';
import React, { useState } from 'react';
import StatusBadge from '@/components/ui/StatusBadge';
import MetalBadge from '@/components/ui/MetalBadge';
import Icon from '@/components/ui/AppIcon';

const ALL_LOTS = [
  { id: 'lot-0848', client: 'Chantier Nord SARL', metal: 'cuivre', priceEst: 281.96, status: 'submitted' as const, date: '04/06', urgent: false },
  { id: 'lot-0847', client: 'Démolition Rhône Est', metal: 'fer', priceEst: 54.00, status: 'submitted' as const, date: '04/06', urgent: false },
  { id: 'lot-0846', client: 'Acier Industrie SA', metal: 'acier', priceEst: 63.00, status: 'submitted' as const, date: '03/06', urgent: true },
  { id: 'lot-0845', client: 'BTP Provence SASU', metal: 'aluminium', priceEst: 175.75, status: 'submitted' as const, date: '03/06', urgent: true },
  { id: 'lot-0844', client: 'Chantier Nord SARL', metal: 'laiton', priceEst: 384.00, status: 'submitted' as const, date: '02/06', urgent: true },
  { id: 'lot-0843', client: 'Électricité Générale', metal: 'cuivre', priceEst: 127.40, status: 'processed' as const, date: '02/06', urgent: false },
  { id: 'lot-0842', client: 'Métal & Co SARL', metal: 'inox', priceEst: 134.00, status: 'invoiced' as const, date: '01/06', urgent: false },
  { id: 'lot-0841', client: 'Chantier Nord SARL', metal: 'fer', priceEst: 96.00, status: 'submitted' as const, date: '01/06', urgent: true },
  { id: 'lot-0840', client: 'Acier Industrie SA', metal: 'cuivre', priceEst: 125.44, status: 'invoiced' as const, date: '31/05', urgent: false },
];

interface Props {
  onSelectLot?: (id: string) => void;
  selectedId?: string;
}

export default function LotListSidebar({ onSelectLot, selectedId = 'lot-0846' }: Props) {
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<'all' | 'submitted' | 'processed' | 'invoiced'>('all');

  const filtered = ALL_LOTS.filter((l) => {
    const matchSearch =
      l.id.includes(search.toLowerCase()) ||
      l.client.toLowerCase().includes(search.toLowerCase()) ||
      l.metal.toLowerCase().includes(search.toLowerCase());
    const matchFilter = filter === 'all' || l.status === filter;
    return matchSearch && matchFilter;
  });

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden flex flex-col" style={{ maxHeight: '80vh' }}>
      <div className="px-4 py-4 border-b border-border space-y-3">
        <div className="relative">
          <Icon name="MagnifyingGlassIcon" size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Rechercher un lot..."
            className="w-full pl-9 pr-3 py-2 rounded-lg border border-border bg-input text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>
        <div className="flex gap-1 bg-muted rounded-lg p-1">
          {(['all', 'submitted', 'processed', 'invoiced'] as const).map((f) => (
            <button
              key={`lot-filter-${f}`}
              onClick={() => setFilter(f)}
              className={`flex-1 py-1 rounded-md text-[11px] font-600 transition-all ${
                filter === f ? 'bg-card text-foreground shadow-card' : 'text-muted-foreground'
              }`}
            >
              {f === 'all' ? 'Tous' : f === 'submitted' ? 'Soumis' : f === 'processed' ? 'Traités' : 'Facturés'}
            </button>
          ))}
        </div>
      </div>

      <div className="overflow-y-auto flex-1 divide-y divide-border">
        {filtered.map((lot) => (
          <button
            key={lot.id}
            onClick={() => onSelectLot?.(lot.id)}
            className={`w-full text-left px-4 py-3.5 transition-colors row-hover ${
              selectedId === lot.id ? 'bg-secondary border-l-2 border-l-primary' : ''
            }`}
          >
            <div className="flex items-center justify-between gap-2 mb-1">
              <div className="flex items-center gap-1.5">
                {lot.urgent && <Icon name="ExclamationCircleIcon" size={13} className="text-amber-600" />}
                <span className="text-xs font-700 text-primary tabular-nums">#{lot.id.toUpperCase()}</span>
              </div>
              <StatusBadge status={lot.status} size="sm" />
            </div>
            <p className="text-sm font-500 text-foreground truncate">{lot.client}</p>
            <div className="flex items-center justify-between mt-1.5">
              <MetalBadge metal={lot.metal} />
              <span className="text-xs tabular-nums font-600 text-foreground">{lot.priceEst.toFixed(2)} $CA</span>
            </div>
            <p className="text-[11px] text-muted-foreground mt-1">{lot.date}</p>
          </button>
        ))}
        {filtered.length === 0 && (
          <div className="py-10 text-center text-sm text-muted-foreground">
            Aucun lot trouvé
          </div>
        )}
      </div>
    </div>
  );
}