'use client';
import React, { useEffect, useState } from 'react';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';
import QRCodeModal from '@/components/ui/QRCodeModal';

interface Container {
  id: string;
  qr_code: string;
  name: string;
  location: string | null;
  status: string;
  created_at: string;
  company_id: string;
}

interface ContainerHeaderProps {
  container: Container;
}

export default function ContainerHeader({ container }: ContainerHeaderProps) {
  const [editing, setEditing] = useState(false);
  const [isAdmin, setIsAdmin] = useState(false);
  const [showQR, setShowQR] = useState(false);

  useEffect(() => {
    const supabase = createClient();
    supabase.auth.getUser().then(({ data: { user } }) => {
      const role = user?.app_metadata?.role ?? user?.user_metadata?.role ?? 'client';
      setIsAdmin(role === 'admin' || role === 'project_admin');
    });
  }, []);

  const statusLabel =
    container.status === 'active' ? 'Actif' :
    container.status === 'inactive' ? 'Inactif' : 'Maintenance';

  const statusClass =
    container.status === 'active' ? 'bg-green-100 text-green-600' :
    container.status === 'inactive' ? 'bg-gray-100 text-gray-500' : 'bg-amber-100 text-amber-600';

  const dotClass =
    container.status === 'active' ? 'bg-green-500 animate-pulse' :
    container.status === 'inactive' ? 'bg-gray-400' : 'bg-amber-500 animate-pulse';

  return (
    <>
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex items-center gap-4">
          <div className="w-14 h-14 rounded-2xl bg-secondary flex items-center justify-center flex-shrink-0">
            <Icon name="ArchiveBoxIcon" size={28} className="text-primary" />
          </div>
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-700 text-foreground">{container.name}</h1>
              <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-600 ${statusClass}`}>
                <div className={`w-1.5 h-1.5 rounded-full ${dotClass}`} />
                {statusLabel}
              </span>
            </div>
            <p className="text-sm text-muted-foreground mt-0.5">
              {container.location ?? 'Emplacement non défini'} · Code : {container.qr_code}
            </p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          {isAdmin && (
            <button
              onClick={() => setShowQR(true)}
              className="flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600 border border-border text-foreground btn-ghost"
            >
              <Icon name="QrCodeIcon" size={16} />
              Générer QR code
            </button>
          )}
          <button
            onClick={() => setEditing(!editing)}
            className="flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600 border border-border text-foreground btn-ghost"
          >
            <Icon name="PencilSquareIcon" size={16} />
            Modifier
          </button>
          <button className="flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600 btn-primary">
            <Icon name="PlusCircleIcon" size={16} className="text-primary-foreground" />
            Nouveau lot
          </button>
          <button className="w-10 h-10 rounded-lg border border-border text-muted-foreground btn-ghost flex items-center justify-center">
            <Icon name="EllipsisVerticalIcon" size={18} />
          </button>
        </div>
      </div>

      {showQR && (
        <QRCodeModal
          containerId={container.id}
          containerName={container.name}
          containerQrCode={container.qr_code}
          onClose={() => setShowQR(false)}
        />
      )}
    </>
  );
}