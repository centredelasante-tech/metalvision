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
  const [error, setError] = useState(false);

  useEffect(() => {
    const supabase = createClient();

    // Build date boundaries anchored to Montreal local time (America/Toronto)
    // so "début du mois" = minuit heure de Montréal, pas minuit UTC.
    const TZ = 'America/Toronto';
    const now = new Date();

    // Extract local date components in the Montreal timezone
    const fmt = (part: Intl.DateTimeFormatPartTypes) =>
      new Intl.DateTimeFormat('en-CA', { timeZone: TZ, [part]: 'numeric' }).format(now);

    const localYear  = parseInt(fmt('year'),  10);
    const localMonth = parseInt(fmt('month'), 10); // 1–12

    // Determine the UTC offset for Montreal at the start of each boundary
    // by constructing the boundary moment and letting Date.UTC handle it.
    // We use a helper: given (y, m, d) in Montreal local time, return ISO string.
    function montrealMidnightISO(y: number, m: number, d: number): string {
      // Create a Date that represents midnight Montreal time.
      // Strategy: build the ISO local string, parse it as UTC, then subtract
      // the offset that Montreal actually has at that moment.
      // Simpler: use the fact that Intl can tell us the offset.
      const candidate = new Date(Date.UTC(y, m - 1, d, 12, 0, 0)); // noon UTC as probe
      const localParts = new Intl.DateTimeFormat('en-CA', {
        timeZone: TZ,
        year: 'numeric', month: '2-digit', day: '2-digit',
        hour: '2-digit', minute: '2-digit', second: '2-digit',
        hour12: false,
      }).formatToParts(candidate);

      const get = (type: string) => parseInt(localParts.find(p => p.type === type)?.value ?? '0', 10);
      // offset in minutes = UTC time - local time (at noon UTC)
      const localHour = get('hour');
      const offsetMinutes = 12 * 60 - (localHour * 60); // noon UTC minus local hour (minutes=0,seconds=0)

      // midnight Montreal = UTC midnight + offsetMinutes
      return new Date(Date.UTC(y, m - 1, d, 0, 0, 0) + offsetMinutes * 60 * 1000).toISOString();
    }

    const monthStart = montrealMidnightISO(localYear, localMonth, 1);
    const monthEnd   = localMonth === 12
      ? montrealMidnightISO(localYear + 1, 1, 1)
      : montrealMidnightISO(localYear, localMonth + 1, 1);
    const yearStart  = montrealMidnightISO(localYear, 1, 1);
    const yearEnd    = montrealMidnightISO(localYear + 1, 1, 1);

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
    ).catch(() => {
      setLoading(false);
      setError(true);
    });
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

  if (error) {
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        {[0, 1, 2, 3].map((i) => (
          <div
            key={i}
            className="rounded-xl border border-destructive/30 bg-destructive/5 p-5 flex items-center gap-3"
          >
            <div className="w-8 h-8 rounded-lg bg-destructive/10 flex items-center justify-center flex-shrink-0">
              <svg
                className="w-4 h-4 text-destructive"
                fill="none"
                viewBox="0 0 24 24"
                strokeWidth={2}
                stroke="currentColor"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
                />
              </svg>
            </div>
            <p className="text-sm text-destructive font-medium">
              Impossible de charger les statistiques
            </p>
          </div>
        ))}
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