import React from 'react';
import QRScannerViewfinder from './QRScannerViewfinder';
import RecentScans from './RecentScans';
import ManualEntry from './ManualEntry';

export default function QRScannerContent() {
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-700 text-foreground">Scanner un conteneur</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Pointez la caméra vers le QR code sur le conteneur ou saisissez l'identifiant manuellement
        </p>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        <div className="xl:col-span-2 space-y-4">
          <QRScannerViewfinder />
          <ManualEntry />
        </div>
        <div>
          <RecentScans />
        </div>
      </div>
    </div>
  );
}