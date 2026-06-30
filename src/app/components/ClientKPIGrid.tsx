'use client';
import React, { useEffect, useState } from 'react';
import MetricCard from '@/components/ui/MetricCard';
import { createClient } from '@/lib/supabase/client';

interface KPIData {
  lotsThisMonth: number;
  lotsSubmittedThisMonth: number;
  pendingValue: number;
  pendingLotsCount: number;
  pendingHasNullPrice: boolean;
  invoicedTotal: number;
  invoicedCount: number;
  activeContainers: number;
  totalContainers: number;
}

function SkeletonCard() {
  return (
    <div className="rounded-xl border border-border bg-card p-5 animate-pulse">
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1 min-w-0">
          <div className="h-3 bg-muted rounded w-32 mb-3" />
          <div className="h-8 bg-muted rounded w-20 mb-2" />
          <div className="h-3 bg-muted rounded w-40" />
        </div>
        <div className="w-10 h-10 rounded-lg bg-muted flex-shrink-0" />
      </div>
    </div>
  );
}

export default function ClientKPIGrid() {
  const [data, setData] = useState<KPIData | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const supabase = createClient();

    const now = new Date();
    const year = now.getFullYear();
    const month = now.getMonth() + 1;
    const monthStart = `${year}-${String(month).padStart(2, '0')}-01`;
    const monthEnd =
      month === 12
        ? `${year + 1}-01-01`
        : `${year}-${String(month + 1).padStart(2, '0')}-01`;
    const yearStart = `${year}-01-01`;
    const yearEnd = `${year + 1}-01-01`;

    Promise.all([
      // 1a. Total lots this month (any status)
      supabase
        .from('raw_measurements')
        .select('*', { count: 'exact', head: true })
        .gte('created_at', monthStart)
        .lt('created_at', monthEnd),

      // 1b. Lots with status='submitted' this month
      supabase
        .from('raw_measurements')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'submitted')
        .gte('created_at', monthStart)
        .lt('created_at', monthEnd),

      // 2. price_paid for status='submitted' (for sum + count)
      supabase
        .from('raw_measurements')
        .select('price_paid')
        .eq('status', 'submitted'),

      // 3. price_paid for status='invoiced' in current year
      supabase
        .from('raw_measurements')
        .select('price_paid')
        .eq('status', 'invoiced')
        .gte('created_at', yearStart)
        .lt('created_at', yearEnd),

      // 4a. Active containers count
      supabase
        .from('containers')
        .select('*', { count: 'exact', head: true })
        .eq('status', 'active'),

      // 4b. Total containers count
      supabase
        .from('containers')
        .select('*', { count: 'exact', head: true }),
    ]).then(
      ([
        lotsMonthRes,
        lotsSubmittedRes,
        pendingPriceRes,
        invoicedPriceRes,
        activeContRes,
        totalContRes,
      ]) => {
        // 1. Lots this month
        const lotsThisMonth = lotsMonthRes.count ?? 0;
        const lotsSubmittedThisMonth = lotsSubmittedRes.count ?? 0;

        // 2. Pending value (status='submitted')
        const pendingRows = (pendingPriceRes.data ?? []) as { price_paid: number | null }[];
        const pendingLotsCount = pendingRows.length;
        let pendingHasNullPrice = false;
        const pendingValue = pendingRows.reduce((acc, row) => {
          if (row.price_paid === null) {
            pendingHasNullPrice = true;
            return acc;
          }
          return acc + row.price_paid;
        }, 0);

        // 3. Invoiced total (current year)
        const invoicedRows = (invoicedPriceRes.data ?? []) as { price_paid: number | null }[];
        const invoicedCount = invoicedRows.length;
        const invoicedTotal = invoicedRows.reduce((acc, row) => {
          if (row.price_paid === null) return acc;
          return acc + row.price_paid;
        }, 0);

        // 4. Containers
        const activeContainers = activeContRes.count ?? 0;
        const totalContainers = totalContRes.count ?? 0;

        setData({
          lotsThisMonth,
          lotsSubmittedThisMonth,
          pendingValue,
          pendingLotsCount,
          pendingHasNullPrice,
          invoicedTotal,
          invoicedCount,
          activeContainers,
          totalContainers,
        });
        setLoading(false);
      }
    );
  }, []);

  if (loading) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <SkeletonCard />
        <SkeletonCard />
        <SkeletonCard />
        <SkeletonCard />
      </div>
    );
  }

  const d = data!;

  const pendingValueStr =
    d.pendingValue > 0
      ? `${d.pendingValue.toFixed(2)} $CA`
      : d.pendingLotsCount > 0
      ? '—' :'0,00 $CA';

  const pendingSubValue = d.pendingHasNullPrice
    ? `${d.pendingLotsCount} lot${d.pendingLotsCount > 1 ? 's' : ''} (certains sans prix)`
    : `${d.pendingLotsCount} lot${d.pendingLotsCount > 1 ? 's' : ''} concerné${d.pendingLotsCount > 1 ? 's' : ''}`;

  const invoicedValueStr = `${d.invoicedTotal.toFixed(2)} $CA`;

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
      <MetricCard
        label="Lots soumis ce mois"
        value={String(d.lotsThisMonth)}
        subValue={`${d.lotsSubmittedThisMonth} en attente de traitement`}
        icon="ClipboardDocumentListIcon"
        trend="neutral"
        trendLabel="Mois calendaire courant"
        variant="default"
      />
      <MetricCard
        label="Valeur estimée en attente"
        value={pendingValueStr}
        subValue={pendingSubValue}
        icon="ClockIcon"
        trend="neutral"
        trendLabel="Lots avec statut soumis"
        variant="accent"
      />
      <MetricCard
        label={`Total facturé (${new Date().getFullYear()})`}
        value={invoicedValueStr}
        subValue={`${d.invoicedCount} lot${d.invoicedCount > 1 ? 's' : ''} facturé${d.invoicedCount > 1 ? 's' : ''} cette année`}
        icon="CurrencyDollarIcon"
        trend="neutral"
        trendLabel="Année calendaire courante"
        variant="positive"
      />
      <MetricCard
        label="Conteneurs actifs"
        value={String(d.activeContainers)}
        subValue={`${d.activeContainers} actifs sur ${d.totalContainers} au total`}
        icon="ArchiveBoxIcon"
        trend="neutral"
        trendLabel="Tous statuts confondus"
        variant="default"
      />
    </div>
  );
}