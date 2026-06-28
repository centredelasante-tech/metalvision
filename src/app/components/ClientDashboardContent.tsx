import React from 'react';
import ClientKPIGrid from './ClientKPIGrid';
import ContainerGrid from './ContainerGrid';
import RecentLotsTable from './RecentLotsTable';
import ClientQuickActions from './ClientQuickActions';

export default function ClientDashboardContent() {
  return (
    <div className="space-y-4 md:space-y-6">
      {/* Page Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-xl md:text-2xl font-700 text-foreground">Tableau de bord</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Chantier Nord — Secteur BTP · Dernière mise à jour 04/06/2026 14:02
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