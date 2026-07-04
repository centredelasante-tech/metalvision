import React from 'react';
import Icon from '@/components/ui/AppIcon';

interface Container {
  id: string;
  qr_code: string;
  name: string;
  location: string | null;
  status: string;
  created_at: string;
  company_id: string;
}

interface ContainerInfoPanelProps {
  container: Container;
}

export default function ContainerInfoPanel({ container }: ContainerInfoPanelProps) {
  const formattedDate = container.created_at
    ? new Date(container.created_at).toLocaleDateString('fr-CA', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      })
    : '—';

  const statusLabel =
    container.status === 'active' ? 'Actif' :
    container.status === 'inactive' ? 'Inactif' : 'Maintenance';

  const INFO_ROWS = [
    { label: 'Identifiant', value: container.qr_code, icon: 'IdentificationIcon' },
    { label: 'Nom', value: container.name, icon: 'ArchiveBoxIcon' },
    { label: 'Localisation', value: container.location ?? '—', icon: 'MapPinIcon' },
    { label: 'Statut', value: statusLabel, icon: 'CheckCircleIcon' },
    { label: 'Créé le', value: formattedDate, icon: 'CalendarIcon' },
  ];

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="px-5 py-4 border-b border-border">
        <h3 className="text-sm font-600 text-foreground">Informations conteneur</h3>
      </div>
      <div className="divide-y divide-border">
        {INFO_ROWS.map((row) => (
          <div key={`info-${row.label}`} className="flex items-center gap-3 px-5 py-3">
            <Icon name={row.icon as Parameters<typeof Icon>[0]['name']} size={16} className="text-muted-foreground flex-shrink-0" />
            <div className="flex-1 min-w-0 flex justify-between gap-2">
              <span className="text-xs text-muted-foreground">{row.label}</span>
              <span className="text-xs font-600 text-foreground text-right truncate">{row.value}</span>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}