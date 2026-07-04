'use client';
import React, { useEffect, useState } from 'react';
import MetricCard from '@/components/ui/MetricCard';
import { createClient } from '@/lib/supabase/client';

interface KPIData {
  lotsEnAttente: number;
  lotsTraitesAujourdhui: number;
  avgConfidence: number | null;
  confidenceCount: number;
  loading: boolean;
}

export default function AdminKPIGrid() {
  const [kpi, setKpi] = useState<KPIData>({
    lotsEnAttente: 0,
    lotsTraitesAujourdhui: 0,
    avgConfidence: null,
    confidenceCount: 0,
    loading: true,
  });

  useEffect(() => {
    const supabase = createClient();

    const fetchKPIs = async () => {
      const todayStart = new Date();
      todayStart.setHours(0, 0, 0, 0);
      const todayISO = todayStart.toISOString();

      const [pendingRes, processedRes, confidenceRes] = await Promise.all([
        supabase
          .from('raw_measurements')
          .select('id', { count: 'exact', head: true })
          .eq('status', 'submitted'),
        supabase
          .from('raw_measurements')
          .select('id', { count: 'exact', head: true })
          .eq('status', 'processed')
          .gte('updated_at', todayISO),
        supabase
          .from('raw_measurements')
          .select('confidence')
          .not('confidence', 'is', null)
          .order('created_at', { ascending: false })
          .limit(30),
      ]);

      const lotsEnAttente = pendingRes.count ?? 0;
      const lotsTraitesAujourdhui = processedRes.count ?? 0;

      let avgConfidence: number | null = null;
      let confidenceCount = 0;
      if (confidenceRes.data && confidenceRes.data.length > 0) {
        confidenceCount = confidenceRes.data.length;
        const sum = confidenceRes.data.reduce(
          (acc, row) => acc + (Number(row.confidence) || 0),
          0
        );
        avgConfidence = sum / confidenceCount;
      }

      setKpi({
        lotsEnAttente,
        lotsTraitesAujourdhui,
        avgConfidence,
        confidenceCount,
        loading: false,
      });
    };

    fetchKPIs();
  }, []);

  if (kpi.loading) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6 gap-4">
        {[1, 2, 3, 4, 5, 6].map((i) => (
          <div key={`kpi-skel-${i}`} className="h-28 bg-muted rounded-xl animate-pulse" />
        ))}
      </div>
    );
  }

  const confidenceDisplay = kpi.avgConfidence !== null
    ? `${kpi.avgConfidence.toFixed(1)}%`
    : '—';
  const confidenceSubValue = kpi.avgConfidence !== null
    ? `Sur les ${kpi.confidenceCount} derniers lots`
    : 'Aucune donnée';

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-6 gap-4">
      <MetricCard
        label="Lots en attente"
        value={String(kpi.lotsEnAttente)}
        subValue={kpi.lotsEnAttente === 0 ? 'Aucun lot en attente' : `${kpi.lotsEnAttente} lot${kpi.lotsEnAttente > 1 ? 's' : ''} à traiter`}
        icon="ClipboardDocumentListIcon"
        trend={kpi.lotsEnAttente > 0 ? 'alert' : 'up'}
        trendLabel={kpi.lotsEnAttente > 0 ? 'Action requise' : 'À jour'}
        variant={kpi.lotsEnAttente > 0 ? 'alert' : 'default'}
      />
      <MetricCard
        label="Traités aujourd'hui"
        value={String(kpi.lotsTraitesAujourdhui)}
        subValue={kpi.lotsTraitesAujourdhui === 0 ? 'Aucun traitement ce jour' : `${kpi.lotsTraitesAujourdhui} lot${kpi.lotsTraitesAujourdhui > 1 ? 's' : ''} traité${kpi.lotsTraitesAujourdhui > 1 ? 's' : ''}`}
        icon="CheckCircleIcon"
        trend={kpi.lotsTraitesAujourdhui > 0 ? 'up' : 'up'}
        trendLabel="Aujourd'hui"
        variant={kpi.lotsTraitesAujourdhui > 0 ? 'positive' : 'default'}
      />
      <MetricCard
        label="Conteneurs ≥ 85%"
        value="0"
        subValue="Capteurs non installés"
        icon="ExclamationTriangleIcon"
        trend="up"
        trendLabel="Aucune donnée"
        variant="default"
      />
      <MetricCard
        label="Factures impayées"
        value="0"
        subValue="Module non disponible"
        icon="DocumentTextIcon"
        trend="up"
        trendLabel="Aucune donnée"
        variant="default"
      />
      <MetricCard
        label="Confiance IA moy."
        value={confidenceDisplay}
        subValue={confidenceSubValue}
        icon="SparklesIcon"
        trend="up"
        trendLabel={kpi.avgConfidence !== null ? 'Calculé depuis la BD' : 'Aucune mesure'}
        variant={kpi.avgConfidence !== null ? 'default' : 'default'}
      />
      <MetricCard
        label="Prix index cuivre"
        value="7,42 $CA"
        subValue="par kg · valeur statique"
        icon="ArrowTrendingUpIcon"
        trend="up"
        trendLabel="Indicatif · LME"
        variant="default"
      />
    </div>
  );
}