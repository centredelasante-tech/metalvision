import React from 'react';
import Icon from '@/components/ui/AppIcon';

export default function SensorPanel() {
  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="SignalIcon" size={16} className="text-muted-foreground" />
          <h3 className="text-sm font-600 text-foreground">Capteur de remplissage</h3>
        </div>
        <span className="text-xs font-600 px-2 py-0.5 rounded-full bg-muted text-muted-foreground">
          Non installé
        </span>
      </div>

      <div className="p-6 flex flex-col items-center justify-center text-center gap-3">
        <div className="w-12 h-12 rounded-xl bg-muted flex items-center justify-center">
          <Icon name="SignalSlashIcon" size={24} className="text-muted-foreground" />
        </div>
        <div>
          <p className="text-sm font-600 text-foreground">Aucun capteur physique installé</p>
          <p className="text-xs text-muted-foreground mt-1 max-w-[220px]">
            Les données de remplissage seront disponibles une fois les capteurs IoT connectés à ce conteneur.
          </p>
        </div>
      </div>
    </div>
  );
}