import React from 'react';
import LotDetailPanel from './LotDetailPanel';
import LotListSidebar from './LotListSidebar';
import ContainersListSection from './ContainersListSection';

export default function LotManagementContent() {
  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-700 text-foreground">Gestion des lots</h1>
          <p className="text-sm text-muted-foreground mt-1">
            Traitez les lots soumis, saisissez les poids réels et générez les factures
          </p>
        </div>
      </div>
      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        <div className="xl:col-span-1">
          <LotListSidebar />
        </div>
        <div className="xl:col-span-2">
          <LotDetailPanel />
        </div>
      </div>
      <ContainersListSection />
    </div>
  );
}