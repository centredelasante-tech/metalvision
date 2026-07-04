import React from 'react';
import Link from 'next/link';
import Icon from '@/components/ui/AppIcon';

export default function SensorAlerts() {
  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="BellAlertIcon" size={18} className="text-muted-foreground" />
          <h3 className="text-sm font-600 text-foreground">Alertes capteurs</h3>
        </div>
        <span className="bg-muted text-muted-foreground text-xs font-700 px-2 py-0.5 rounded-full">
          0
        </span>
      </div>

      <div className="py-10 px-5 text-center">
        <div className="w-12 h-12 rounded-xl bg-muted flex items-center justify-center mx-auto mb-3">
          <Icon name="SignalSlashIcon" size={22} className="text-muted-foreground" />
        </div>
        <p className="text-sm font-600 text-foreground">Aucune donnée capteur</p>
        <p className="text-xs text-muted-foreground mt-1 leading-relaxed">
          Les capteurs physiques ne sont pas encore installés sur les conteneurs.
        </p>
      </div>

      <div className="px-5 py-3 border-t border-border">
        <Link href="/lot-management" className="text-xs text-primary font-600 hover:underline flex items-center gap-1">
          Gérer les conteneurs
          <Icon name="ArrowRightIcon" size={12} />
        </Link>
      </div>
    </div>
  );
}