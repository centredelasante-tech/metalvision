'use client';
import React, { useEffect, useState } from 'react';
import Link from 'next/link';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';

type ContainerStatus = 'active' | 'inactive' | 'maintenance';

interface Container {
  id: string;
  name: string;
  location: string;
  status: ContainerStatus;
}

function StatusBadge({ status }: { status: ContainerStatus }) {
  const config: Record<ContainerStatus, { label: string; className: string }> = {
    active: { label: 'Actif', className: 'bg-green-100 text-green-700' },
    inactive: { label: 'Inactif', className: 'bg-gray-100 text-gray-500' },
    maintenance: { label: 'Maintenance', className: 'bg-orange-100 text-orange-600' },
  };
  const { label, className } = config[status] ?? config.inactive;
  return (
    <span className={`text-[11px] font-500 px-2 py-0.5 rounded-full flex-shrink-0 ${className}`}>
      {label}
    </span>
  );
}

export default function ContainerGrid() {
  const [containers, setContainers] = useState<Container[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const supabase = createClient();
    supabase
      .from('containers')
      .select('id, name, location, status')
      .order('created_at', { ascending: false })
      .limit(10)
      .then(({ data, error: err }) => {
        if (err) {
          setError('Impossible de charger les conteneurs. Veuillez réessayer.');
        } else {
          setContainers((data as Container[]) ?? []);
        }
        setLoading(false);
      });
  }, []);

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <h2 className="text-sm font-600 text-foreground">Mes conteneurs</h2>
        <Link href="/container-detail" className="text-xs text-primary font-600 hover:underline">
          Voir tout
        </Link>
      </div>

      {loading && (
        <div className="divide-y divide-border">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="flex items-center gap-3 px-5 py-3.5">
              <div className="w-9 h-9 rounded-lg bg-muted animate-pulse flex-shrink-0" />
              <div className="flex-1 space-y-2">
                <div className="h-3 bg-muted rounded animate-pulse w-1/3" />
                <div className="h-2.5 bg-muted rounded animate-pulse w-2/3" />
              </div>
            </div>
          ))}
        </div>
      )}

      {!loading && error && (
        <div className="px-5 py-8 text-center">
          <Icon name="ExclamationCircleIcon" size={24} className="text-red-400 mx-auto mb-2" />
          <p className="text-sm text-red-500">{error}</p>
        </div>
      )}

      {!loading && !error && containers.length === 0 && (
        <div className="px-5 py-8 text-center">
          <Icon name="ArchiveBoxIcon" size={24} className="text-muted-foreground mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">Aucun conteneur pour le moment.</p>
        </div>
      )}

      {!loading && !error && containers.length > 0 && (
        <div className="divide-y divide-border">
          {containers.map((c) => (
            <Link
              key={c.id}
              href="/container-detail"
              className="flex items-center gap-3 px-5 py-3.5 row-hover transition-colors"
            >
              <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 bg-muted">
                <Icon name="ArchiveBoxIcon" size={18} className="text-muted-foreground" />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between gap-2">
                  <span className="text-sm font-600 text-foreground truncate">{c.name}</span>
                  <StatusBadge status={(c.status as ContainerStatus) ?? 'inactive'} />
                </div>
                <p className="text-xs text-muted-foreground truncate">{c.location}</p>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}