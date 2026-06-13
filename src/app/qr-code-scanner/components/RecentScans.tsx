'use client';
import React from 'react';
import Link from 'next/link';
import Icon from '@/components/ui/AppIcon';

const RECENT_SCANS = [
  { id: 'scan-1', containerId: 'CT-001', location: 'Zone A — Entrée', time: 'Il y a 2h', lots: 3 },
  { id: 'scan-2', containerId: 'CT-003', location: 'Zone C — Stockage', time: 'Il y a 1j', lots: 7 },
  { id: 'scan-3', containerId: 'CT-002', location: 'Zone B — Atelier', time: 'Il y a 2j', lots: 2 },
  { id: 'scan-4', containerId: 'CT-001', location: 'Zone A — Entrée', time: 'Il y a 4j', lots: 5 },
  { id: 'scan-5', containerId: 'CT-004', location: 'Zone D — Parking', time: 'Il y a 1sem', lots: 1 },
];

export default function RecentScans() {
  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="ClockIcon" size={16} className="text-muted-foreground" />
          <h3 className="text-sm font-600 text-foreground">Scans récents</h3>
        </div>
        <span className="text-xs text-muted-foreground">{RECENT_SCANS?.length} conteneurs</span>
      </div>
      <div className="divide-y divide-border">
        {RECENT_SCANS?.map((scan) => (
          <Link
            key={scan?.id}
            href="/container-detail"
            className="flex items-center gap-3 px-5 py-3.5 row-hover transition-colors"
          >
            <div className="w-8 h-8 rounded-lg bg-secondary flex items-center justify-center flex-shrink-0">
              <Icon name="ArchiveBoxIcon" size={16} className="text-primary" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm font-600 text-foreground">{scan?.containerId}</span>
                <span className="text-xs bg-muted text-muted-foreground px-1.5 py-0.5 rounded tabular-nums">
                  {scan?.lots} lot{scan?.lots > 1 ? 's' : ''}
                </span>
              </div>
              <p className="text-xs text-muted-foreground truncate">{scan?.location}</p>
              <p className="text-[11px] text-muted-foreground mt-0.5">{scan?.time}</p>
            </div>
            <Icon name="ChevronRightIcon" size={14} className="text-muted-foreground flex-shrink-0" />
          </Link>
        ))}
      </div>
      <div className="px-5 py-3 border-t border-border">
        <p className="text-xs text-muted-foreground text-center">
          Appuyez sur un conteneur pour accéder directement à sa page
        </p>
      </div>
    </div>
  );
}