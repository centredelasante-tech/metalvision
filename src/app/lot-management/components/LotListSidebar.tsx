'use client';
import React, { useEffect, useState } from 'react';
import StatusBadge from '@/components/ui/StatusBadge';
import MetalBadge from '@/components/ui/MetalBadge';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';

type LotStatus = 'submitted' | 'processed' | 'invoiced';

interface Lot {
  id: string;
  lotNumber: string;
  client: string;
  metal: string;
  priceEst: number;
  status: LotStatus;
  date: string;
}

interface Props {
  onSelectLot?: (id: string) => void;
  selectedId?: string;
}

export default function LotListSidebar({ onSelectLot, selectedId }: Props) {
  const [lots, setLots] = useState<Lot[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState<'all' | LotStatus>('all');

  useEffect(() => {
    const supabase = createClient();
    const fetchLots = async () => {
      const { data, error } = await supabase
        .from('raw_measurements')
        .select('id, metal_type_predicted, volume_estimated_m3, price_paid, status, created_at, company_id, companies(name)')
        .order('created_at', { ascending: false });

      if (error) {
        console.error('Error fetching lots:', error.message);
        setLoading(false);
        return;
      }

      const mapped: Lot[] = (data ?? []).map((row: any) => {
        const shortId = row.id.replace(/-/g, '').substring(0, 6).toUpperCase();
        const rawStatus = row.status as string;
        const validStatuses: LotStatus[] = ['submitted', 'processed', 'invoiced'];
        const status: LotStatus = validStatuses.includes(rawStatus as LotStatus)
          ? (rawStatus as LotStatus)
          : 'submitted';
        const dateObj = row.created_at ? new Date(row.created_at) : null;
        const date = dateObj
          ? `${String(dateObj.getDate()).padStart(2, '0')}/${String(dateObj.getMonth() + 1).padStart(2, '0')}`
          : '—';
        const companyName = row.companies?.name ?? '—';
        return {
          id: row.id,
          lotNumber: `LOT-${shortId}`,
          client: companyName,
          metal: row.metal_type_predicted ?? 'inconnu',
          priceEst: Number(row.price_paid ?? 0),
          status,
          date,
        };
      });

      setLots(mapped);
      setLoading(false);
    };

    fetchLots();
  }, []);

  const filtered = lots.filter((l) => {
    const matchSearch =
      l.lotNumber.toLowerCase().includes(search.toLowerCase()) ||
      l.client.toLowerCase().includes(search.toLowerCase()) ||
      l.metal.toLowerCase().includes(search.toLowerCase());
    const matchFilter = filter === 'all' || l.status === filter;
    return matchSearch && matchFilter;
  });

  if (loading) {
    return (
      <div className="bg-card rounded-xl border border-border overflow-hidden flex flex-col" style={{ maxHeight: '80vh' }}>
        <div className="px-4 py-4 border-b border-border space-y-3">
          <div className="h-9 bg-muted rounded-lg animate-pulse" />
          <div className="h-8 bg-muted rounded-lg animate-pulse" />
        </div>
        <div className="p-4 space-y-3">
          {[1, 2, 3, 4].map((i) => (
            <div key={`skel-${i}`} className="h-16 bg-muted rounded-lg animate-pulse" />
          ))}
        </div>
      </div>
    );
  }

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
              <span className="text-xs font-700 text-primary tabular-nums">#{lot.lotNumber}</span>
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