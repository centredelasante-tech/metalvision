import React from 'react';
import ClientKPIGrid from './ClientKPIGrid';
import ContainerGrid from './ContainerGrid';
import RecentLotsTable from './RecentLotsTable';
import ClientQuickActions from './ClientQuickActions';

export default function ClientDashboardContent() {
  return (
    <div className="space-y-6">
      {/* Page Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-700 text-foreground">Tableau de bord</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Chantier Nord — Secteur BTP · Dernière mise à jour 04/06/2026 14:02
          </p>
        </div>
        <ClientQuickActions />
      </div>

      {/* KPI Cards */}
      <ClientKPIGrid />

      {/* Two-column layout */}
      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
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