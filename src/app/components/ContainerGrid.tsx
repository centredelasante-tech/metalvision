'use client';
import React from 'react';
import Link from 'next/link';
import Icon from '@/components/ui/AppIcon';

const CONTAINERS = [
  {
    id: 'ct-001',
    name: 'CT-001',
    location: 'Zone A — Entrée chantier',
    fillLevel: 78,
    hasSensor: true,
    lastActivity: 'Il y a 2h',
    status: 'active' as const,
  },
  {
    id: 'ct-002',
    name: 'CT-002',
    location: 'Zone B — Atelier',
    fillLevel: 45,
    hasSensor: false,
    lastActivity: 'Il y a 1j',
    status: 'active' as const,
  },
  {
    id: 'ct-003',
    name: 'CT-003',
    location: 'Zone C — Stockage',
    fillLevel: 92,
    hasSensor: true,
    lastActivity: 'Il y a 4h',
    status: 'critical' as const,
  },
  {
    id: 'ct-004',
    name: 'CT-004',
    location: 'Zone D — Parking',
    fillLevel: 20,
    hasSensor: false,
    lastActivity: 'Il y a 3j',
    status: 'active' as const,
  },
];

export default function ContainerGrid() {
  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <h2 className="text-sm font-600 text-foreground">Mes conteneurs</h2>
        <Link href="/container-detail" className="text-xs text-primary font-600 hover:underline">
          Voir tout
        </Link>
      </div>
      <div className="divide-y divide-border">
        {CONTAINERS.map((c) => (
          <Link
            key={c.id}
            href="/container-detail"
            className="flex items-center gap-3 px-5 py-3.5 row-hover transition-colors"
          >
            <div className={`w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 ${
              c.status === 'critical' ? 'bg-red-100' : 'bg-muted'
            }`}>
              <Icon
                name="ArchiveBoxIcon"
                size={18}
                className={c.status === 'critical' ? 'text-red-600' : 'text-muted-foreground'}
              />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-600 text-foreground">{c.name}</span>
                {c.hasSensor && (
                  <Icon name="SignalIcon" size={14} className="text-primary flex-shrink-0" />
                )}
              </div>
              <p className="text-xs text-muted-foreground truncate">{c.location}</p>
              <div className="flex items-center gap-2 mt-1.5">
                <div className="flex-1 h-1.5 bg-muted rounded-full overflow-hidden">
                  <div
                    className={`h-full rounded-full transition-all ${
                      c.fillLevel >= 85 ? 'bg-red-500' :
                      c.fillLevel >= 60 ? 'bg-accent' : 'bg-primary'
                    }`}
                    style={{ width: `${c.fillLevel}%` }}
                  />
                </div>
                <span className="text-[11px] tabular-nums text-muted-foreground flex-shrink-0">
                  {c.fillLevel}%
                </span>
              </div>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}