'use client';
import React, { useEffect, useState } from 'react';
import ClientKPIGrid from './ClientKPIGrid';
import ContainerGrid from './ContainerGrid';
import RecentLotsTable from './RecentLotsTable';
import ClientQuickActions from './ClientQuickActions';
import { createClient } from '@/lib/supabase/client';
import { useAuth } from '@/contexts/AuthContext';

export default function ClientDashboardContent() {
  const { user } = useAuth();
  const [companyName, setCompanyName] = useState<string | null>(null);
  const [lastUpdate, setLastUpdate] = useState<string>('');

  useEffect(() => {
    // Format current time in French (dd/mm/yyyy hh:mm)
    const now = new Date();
    const formatted = new Intl.DateTimeFormat('fr-CA', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
      timeZone: 'America/Toronto',
    }).format(now).replace(',', '');
    setLastUpdate(formatted);
  }, []);

  useEffect(() => {
    if (!user) return;
    const supabase = createClient();
    supabase
      .from('company_members')
      .select('companies(name)')
      .eq('user_id', user.id)
      .limit(1)
      .single()
      .then(({ data }) => {
        const name = (data?.companies as { name: string } | null)?.name ?? null;
        setCompanyName(name);
      });
  }, [user]);

  const subtitle = companyName
    ? `${companyName} · Dernière mise à jour ${lastUpdate}`
    : lastUpdate
    ? `Dernière mise à jour ${lastUpdate}`
    : '';

  return (
    <div className="space-y-4 md:space-y-6">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-xl md:text-2xl font-700 text-foreground">Tableau de bord</h1>
          <p className="text-sm text-muted-foreground mt-1">
            {subtitle}
          </p>
        </div>
        <ClientQuickActions />
      </div>

      {/* KPI Cards */}
      <ClientKPIGrid />

      {/* Two-column layout */}
      <div className="flex flex-col xl:grid xl:grid-cols-3 gap-4 md:gap-6">
        <div className="xl:col-span-2">
          <RecentLotsTable />
        </div>
        <div>
          <ContainerGrid />
        </div>
      </div>
    </div>
  );
}