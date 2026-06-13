import React from 'react';
import Icon from '@/components/ui/AppIcon';

const INFO_ROWS = [
  { label: 'Identifiant', value: 'CT-003', icon: 'IdentificationIcon' },
  { label: 'Entreprise', value: 'Acier Industrie SA', icon: 'BuildingOfficeIcon' },
  { label: 'Localisation', value: 'Zone C — Stockage, Bâtiment 3', icon: 'MapPinIcon' },
  { label: 'Type', value: 'Benne 10 m³', icon: 'ArchiveBoxIcon' },
  { label: 'Capteur', value: 'Ultrason · ID SEN-042', icon: 'SignalIcon' },
  { label: 'Créé le', value: '12/01/2026', icon: 'CalendarIcon' },
  { label: 'Dernière collecte', value: '15/05/2026', icon: 'TruckIcon' },
];

export default function ContainerInfoPanel() {
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