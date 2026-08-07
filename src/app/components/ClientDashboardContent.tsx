'use client';
import React, { useEffect, useState } from 'react';
import ClientKPIGrid from './ClientKPIGrid';
import ContainerGrid from './ContainerGrid';
import RecentLotsTable from './RecentLotsTable';
import ClientQuickActions from './ClientQuickActions';
import CCFDashboardSection from './CCFDashboardSection';
import { createClient } from '@/lib/supabase/client';

export default function ClientDashboardContent() {
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
    // Note (INC-S01-01) : `useAuth()` n'est fourni par aucun `AuthProvider`
    // monté dans l'arbre — `user` y est toujours `undefined`. Utilisation
    // directe de `supabase.auth.getUser()`, comme dans Sidebar.tsx.
    // Table/colonnes également corrigées : `company_members`/`companies`
    // ont été renommées `organization_members`/`organizations` lors du
    // rebuild CCF (MVP-DA-012) — l'ancien nom n'existe plus (PGRST205).
    const supabase = createClient();
    supabase.auth.getUser().then(({ data: { user } }) => {
      if (!user) return;
      supabase
        .from('organization_members')
        .select('organizations(name)')
        .eq('user_id', user.id)
        .limit(1)
        .single()
        .then(({ data }) => {
          const orgsRel: any = (data as any)?.organizations ?? null;
          const name: string | null = Array.isArray(orgsRel) ? orgsRel[0]?.name ?? null : orgsRel?.name ?? null;
          if (name) {
            setCompanyName(name);
            return;
          }
          // (#533) Un primary_admin de regroupement n'a aucune ligne
          // organization_members (cf. Sidebar.tsx pour le détail) — la
          // requête ci-dessus ne renvoie donc jamais de nom pour ce rôle.
          // Repli explicite sur le nom du regroupement plutôt que de laisser
          // le sous-titre du tableau de bord silencieusement amputé.
          supabase
            .from('aggregator_admins')
            .select('aggregators(name)')
            .eq('user_id', user.id)
            .eq('role', 'primary_admin')
            .is('revoked_at', null)
            .limit(1)
            .maybeSingle()
            .then(({ data: aggData }) => {
              const aggregatorsRel: any = (aggData as any)?.aggregators ?? null;
              const aggName: string | null = Array.isArray(aggregatorsRel)
                ? aggregatorsRel[0]?.name ?? null
                : aggregatorsRel?.name ?? null;
              setCompanyName(aggName);
            });
        });
    });
  }, []);

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

      {/* CCF Section */}
      <CCFDashboardSection />
    </div>
  );
}