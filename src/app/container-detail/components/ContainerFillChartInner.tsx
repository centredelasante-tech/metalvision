'use client';
import React from 'react';
import Icon from '@/components/ui/AppIcon';

export default function ContainerFillChartInner() {
  return (
    <div className="bg-card rounded-xl border border-border p-5">
      <div className="flex items-center justify-between mb-5">
        <div>
          <h3 className="text-sm font-600 text-foreground">Évolution du niveau de remplissage</h3>
          <p className="text-xs text-muted-foreground mt-0.5">Données capteur ultrason</p>
        </div>
        <div className="flex items-center gap-1.5">
          <div className="w-2.5 h-2.5 rounded-full bg-red-500" />
          <span className="text-xs text-muted-foreground">Seuil critique (85%)</span>
        </div>
      </div>

      <div className="flex flex-col items-center justify-center py-10 gap-3 text-center">
        <div className="w-12 h-12 rounded-xl bg-muted flex items-center justify-center">
          <Icon name="ChartBarIcon" size={24} className="text-muted-foreground" />
        </div>
        <div>
          <p className="text-sm font-600 text-foreground">Aucune donnée de capteur disponible</p>
          <p className="text-xs text-muted-foreground mt-1 max-w-[260px]">
            L&apos;historique de remplissage s&apos;affichera ici une fois les capteurs IoT installés et connectés.
          </p>
        </div>
      </div>
    </div>
  );
}