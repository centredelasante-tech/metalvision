import React from 'react';
import AdminKPIGrid from './AdminKPIGrid';
import PendingLotsTable from './PendingLotsTable';
import AdminCharts from './AdminCharts';
import SensorAlerts from './SensorAlerts';

export default function AdminDashboardContent() {
  return (
    <div className="space-y-4 md:space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
        <div>
          <h1 className="text-xl md:text-2xl font-700 text-foreground">Tableau de bord opérateur</h1>
          <p className="text-sm text-muted-foreground mt-1">
            MetalVision Récupération — 04/06/2026 14:02 · Données en temps réel
          </p>
        </div>
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1.5 px-3 py-1.5 bg-secondary rounded-lg">
            <div className="w-2 h-2 bg-primary rounded-full animate-pulse" />
            <span className="text-xs font-600 text-primary">Opérationnel</span>
          </div>
        </div>
      </div>

      <AdminKPIGrid />

      <div className="flex flex-col xl:grid xl:grid-cols-3 gap-4 md:gap-6">
        <div className="xl:col-span-2">
          <PendingLotsTable />
        </div>
        <div>
          <SensorAlerts />
        </div>
      </div>

      <AdminCharts />
    </div>
  );
}