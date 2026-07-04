'use client';
import React, { useEffect, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';
import Link from 'next/link';
import QRCodeModal from '@/components/ui/QRCodeModal';

interface Container {
  id: string;
  qr_code: string;
  name: string;
  location: string | null;
  status: string;
  created_at: string;
}

interface QRTarget {
  id: string;
  name: string;
  qr_code: string;
}

export default function ContainersListSection() {
  const [containers, setContainers] = useState<Container[]>([]);
  const [loading, setLoading] = useState(true);
  const [isAdmin, setIsAdmin] = useState(false);
  const [qrTarget, setQrTarget] = useState<QRTarget | null>(null);

  useEffect(() => {
    const supabase = createClient();

    const init = async () => {
      const { data: { user } } = await supabase.auth.getUser();
      const role = user?.app_metadata?.role ?? user?.user_metadata?.role ?? 'client';
      const normalised = role === 'admin' || role === 'project_admin' ? 'admin' : role;
      setIsAdmin(normalised === 'admin');

      const { data } = await supabase
        .from('containers')
        .select('id, qr_code, name, location, status, created_at')
        .order('created_at', { ascending: false });

      setContainers(data ?? []);
      setLoading(false);
    };

    init();
  }, []);

  const statusLabel = (s: string) =>
    s === 'active' ? 'Actif' : s === 'inactive' ? 'Inactif' : 'Maintenance';

  const statusClass = (s: string) =>
    s === 'active' ?'bg-green-100 text-green-700'
      : s === 'inactive' ?'bg-gray-100 text-gray-500' :'bg-amber-100 text-amber-600';

  if (loading) {
    return (
      <div className="bg-card rounded-xl border border-border p-6">
        <div className="space-y-3">
          {[1, 2, 3].map((i) => (
            <div key={`skel-${i}`} className="h-12 bg-muted rounded-lg animate-pulse" />
          ))}
        </div>
      </div>
    );
  }

  return (
    <>
      <div className="bg-card rounded-xl border border-border overflow-hidden">
        <div className="flex items-center justify-between px-5 py-4 border-b border-border">
          <div className="flex items-center gap-2">
            <Icon name="ArchiveBoxIcon" size={16} className="text-muted-foreground" />
            <h3 className="text-sm font-600 text-foreground">Conteneurs</h3>
            <span className="text-xs bg-muted text-muted-foreground px-2 py-0.5 rounded-full tabular-nums">
              {containers.length}
            </span>
          </div>
        </div>

        {containers.length === 0 ? (
          <div className="py-10 text-center text-sm text-muted-foreground">
            Aucun conteneur trouvé
          </div>
        ) : (
          <div className="divide-y divide-border">
            {containers.map((c) => (
              <div key={c.id} className="flex items-center gap-3 px-5 py-3.5 row-hover">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-600 text-foreground truncate">{c.name}</span>
                    <span className={`text-[11px] font-600 px-2 py-0.5 rounded-full ${statusClass(c.status)}`}>
                      {statusLabel(c.status)}
                    </span>
                  </div>
                  <p className="text-xs text-muted-foreground mt-0.5 font-mono">{c.qr_code}</p>
                  {c.location && (
                    <p className="text-xs text-muted-foreground truncate">{c.location}</p>
                  )}
                </div>
                <div className="flex items-center gap-2 flex-shrink-0">
                  {isAdmin && (
                    <button
                      onClick={() => setQrTarget({ id: c.id, name: c.name, qr_code: c.qr_code })}
                      className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-600 border border-border btn-ghost"
                    >
                      <Icon name="QrCodeIcon" size={13} />
                      QR code
                    </button>
                  )}
                  <Link
                    href={`/container-detail/${c.id}`}
                    className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-600 btn-primary"
                  >
                    <Icon name="ArrowTopRightOnSquareIcon" size={13} className="text-primary-foreground" />
                    Voir
                  </Link>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {qrTarget && (
        <QRCodeModal
          containerId={qrTarget.id}
          containerName={qrTarget.name}
          containerQrCode={qrTarget.qr_code}
          onClose={() => setQrTarget(null)}
        />
      )}
    </>
  );
}
