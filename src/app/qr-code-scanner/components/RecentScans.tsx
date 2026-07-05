'use client';
import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';

interface ScanEvent {
  id: string;
  container_id: string;
  action_type: string;
  scanned_at: string;
  containers?: { id: string; name: string; qr_code: string } | null;
  lot_count?: number;
}

function timeAgo(isoDate: string): string {
  const diff = Date.now() - new Date(isoDate).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 60) return `Il y a ${minutes}min`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `Il y a ${hours}h`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `Il y a ${days}j`;
  return `Il y a ${Math.floor(days / 7)}sem`;
}

export default function RecentScans() {
  const [scans, setScans] = useState<ScanEvent[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const supabase = createClient();

    supabase
      .from('scan_events')
      .select('id, container_id, action_type, scanned_at, containers(id, name, qr_code)')
      .order('scanned_at', { ascending: false })
      .limit(5)
      .then(async ({ data, error }) => {
        if (error || !data) {
          setLoading(false);
          return;
        }

        // For each scan, count lots in that container
        const containerIds = [...new Set(data.map((s) => s.container_id).filter(Boolean))] as string[];
        let lotCountMap: Record<string, number> = {};
        if (containerIds.length > 0) {
          const { data: lotCounts } = await supabase
            .from('raw_measurements')
            .select('container_id')
            .in('container_id', containerIds);
          if (lotCounts) {
            lotCounts.forEach((row: { container_id: string }) => {
              lotCountMap[row.container_id] = (lotCountMap[row.container_id] ?? 0) + 1;
            });
          }
        }

        const enriched = data.map((s) => ({
          ...s,
          containers: s.containers as ScanEvent['containers'],
          lot_count: lotCountMap[s.container_id] ?? 0,
        }));

        setScans(enriched);
        setLoading(false);
      });
  }, []);

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="ClockIcon" size={16} className="text-muted-foreground" />
          <h3 className="text-sm font-600 text-foreground">Scans récents</h3>
        </div>
        <span className="text-xs text-muted-foreground">{scans.length} conteneur{scans.length !== 1 ? 's' : ''}</span>
      </div>

      {loading && (
        <div className="divide-y divide-border">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="flex items-center gap-3 px-5 py-3.5">
              <div className="w-8 h-8 rounded-lg bg-muted animate-pulse flex-shrink-0" />
              <div className="flex-1 space-y-2">
                <div className="h-3 bg-muted rounded animate-pulse w-1/3" />
                <div className="h-2.5 bg-muted rounded animate-pulse w-2/3" />
              </div>
            </div>
          ))}
        </div>
      )}

      {!loading && scans.length === 0 && (
        <div className="px-5 py-8 text-center">
          <Icon name="QrCodeIcon" size={24} className="text-muted-foreground mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">Aucun scan récent.</p>
        </div>
      )}

      {!loading && scans.length > 0 && (
        <div className="divide-y divide-border">
          {scans.map((scan) => {
            const container = scan.containers;
            const containerId = container?.id ?? scan.container_id;
            const containerName = container?.qr_code ?? scan.container_id.slice(0, 8).toUpperCase();
            const lots = scan.lot_count ?? 0;

            return (
              <Link
                key={scan.id}
                href={`/container-detail/${containerId}`}
                className="flex items-center gap-3 px-5 py-3.5 row-hover transition-colors"
              >
                <div className="w-8 h-8 rounded-lg bg-secondary flex items-center justify-center flex-shrink-0">
                  <Icon name="ArchiveBoxIcon" size={16} className="text-primary" />
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center justify-between gap-2">
                    <span className="text-sm font-600 text-foreground">{containerName}</span>
                    <span className="text-xs bg-muted text-muted-foreground px-1.5 py-0.5 rounded tabular-nums">
                      {lots} lot{lots !== 1 ? 's' : ''}
                    </span>
                  </div>
                  <p className="text-xs text-muted-foreground truncate">{container?.name ?? '—'}</p>
                  <p className="text-[11px] text-muted-foreground mt-0.5">{timeAgo(scan.scanned_at)}</p>
                </div>
                <Icon name="ChevronRightIcon" size={14} className="text-muted-foreground flex-shrink-0" />
              </Link>
            );
          })}
        </div>
      )}

      <div className="px-5 py-3 border-t border-border">
        <p className="text-xs text-muted-foreground text-center">
          Appuyez sur un conteneur pour accéder directement à sa page
        </p>
      </div>
    </div>
  );
}