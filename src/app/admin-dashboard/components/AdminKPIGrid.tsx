import React from 'react';
import MetricCard from '@/components/ui/MetricCard';

export default function AdminKPIGrid() {
  // Grid plan: 6 cards → 3×2 → row1: 3 cards, row2: 3 cards
  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6 gap-4">
      <MetricCard
        label="Lots en attente"
        value="7"
        subValue="4 depuis plus de 24h"
        icon="ClipboardDocumentListIcon"
        trend="alert"
        trendLabel="Action requise"
        variant="alert"
      />
      <MetricCard
        label="Traités aujourd'hui"
        value="12"
        subValue="Valeur : 1 847 $CA"
        icon="CheckCircleIcon"
        trend="up"
        trendLabel="+3 vs hier"
        variant="positive"
      />
      <MetricCard
        label="Conteneurs ≥ 85%"
        value="3"
        subValue="CT-003, CT-007, CT-014"
        icon="ExclamationTriangleIcon"
        trend="alert"
        trendLabel="Collecte urgente"
        variant="alert"
      />
      <MetricCard
        label="Factures impayées"
        value="9"
        subValue="Total : 3 240 $CA"
        icon="DocumentTextIcon"
        trend="down"
        trendLabel="-2 depuis hier"
        variant="accent"
      />
      <MetricCard
        label="Confiance IA moy."
        value="88.4%"
        subValue="Sur les 30 derniers lots"
        icon="SparklesIcon"
        trend="up"
        trendLabel="+1.2% ce mois"
        variant="default"
      />
      <MetricCard
        label="Prix index cuivre"
        value="7,42 $CA"
        subValue="par kilogramme · LME"
        icon="ArrowTrendingUpIcon"
        trend="up"
        trendLabel="+0,18 $CA vs hier"
        variant="positive"
      />
    </div>
  );
}