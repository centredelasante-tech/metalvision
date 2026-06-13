import React from 'react';
import MetricCard from '@/components/ui/MetricCard';

export default function ClientKPIGrid() {
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
      <MetricCard
        label="Lots soumis ce mois"
        value="14"
        subValue="3 en attente de traitement"
        icon="ClipboardDocumentListIcon"
        trend="up"
        trendLabel="+3 vs mois dernier"
        variant="default"
      />
      <MetricCard
        label="Valeur estimée en attente"
        value="834 $CA"
        subValue="3 lots non encore traités"
        icon="ClockIcon"
        trend="alert"
        trendLabel="Lots en attente depuis 2j"
        variant="accent"
      />
      <MetricCard
        label="Total facturé (2026)"
        value="4 280 $CA"
        subValue="11 lots traités et facturés"
        icon="CurrencyDollarIcon"
        trend="up"
        trendLabel="+18% vs 2025"
        variant="positive"
      />
      <MetricCard
        label="Conteneurs actifs"
        value="4"
        subValue="1 capteur connecté"
        icon="ArchiveBoxIcon"
        trend="neutral"
        trendLabel="Tous opérationnels"
        variant="default"
      />
    </div>
  );
}