'use client';
import React, { useState } from 'react';
import Icon from '@/components/ui/AppIcon';
import QRScannerViewfinder from './QRScannerViewfinder';
import ManualEntry from './ManualEntry';
import ContainerResult from './ContainerResult';

export type ContainerData = {
  id: string;
  name: string;
  location: string | null;
  status: string;
  company_id: string;
  qr_code: string;
};

type Tab = 'scanner' | 'manual';

export default function QRScannerContent() {
  const [activeTab, setActiveTab] = useState<Tab>('scanner');
  const [result, setResult] = useState<ContainerData | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleResult = (container: ContainerData | null, err: string | null) => {
    setResult(container);
    setError(err);
  };

  const handleReset = () => {
    setResult(null);
    setError(null);
  };

  return (
    <div className="space-y-4 md:space-y-6">
      {/* Page Header */}
      <div>
        <h1 className="text-xl md:text-2xl font-700 text-foreground">Scanner un conteneur</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Pointez la caméra vers le QR code ou saisissez l'identifiant manuellement
        </p>
      </div>

      {/* Tab Toggle */}
      <div className="flex gap-1 p-1 bg-muted rounded-xl w-fit">
        <button
          onClick={() => { setActiveTab('scanner'); handleReset(); }}
          className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-600 transition-all duration-150 ${
            activeTab === 'scanner' ?'bg-card text-foreground shadow-sm' :'text-muted-foreground hover:text-foreground'
          }`}
        >
          <Icon name="CameraIcon" size={16} />
          Scanner
        </button>
        <button
          onClick={() => { setActiveTab('manual'); handleReset(); }}
          className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-600 transition-all duration-150 ${
            activeTab === 'manual' ?'bg-card text-foreground shadow-sm' :'text-muted-foreground hover:text-foreground'
          }`}
        >
          <Icon name="PencilSquareIcon" size={16} />
          Saisie manuelle
        </button>
      </div>

      {/* Main Content */}
      <div className="flex flex-col xl:grid xl:grid-cols-3 gap-4 md:gap-6">
        <div className="xl:col-span-2 space-y-4">
          {activeTab === 'scanner' ? (
            <QRScannerViewfinder onResult={handleResult} />
          ) : (
            <ManualEntry onResult={handleResult} />
          )}

          {/* Result / Error Panel */}
          {(result || error) && (
            <ContainerResult
              container={result}
              error={error}
              onReset={handleReset}
            />
          )}
        </div>

        {/* Info Panel */}
        <div className="space-y-4">
          <div className="bg-card rounded-xl border border-border p-5">
            <div className="flex items-center gap-2 mb-3">
              <Icon name="InformationCircleIcon" size={16} className="text-primary" />
              <h3 className="text-sm font-600 text-foreground">Comment ça marche</h3>
            </div>
            <ol className="space-y-3">
              {[
                { icon: 'QrCodeIcon', text: 'Scannez le QR code collé sur le conteneur ou entrez son code manuellement.' },
                { icon: 'MagnifyingGlassIcon', text: 'Le système vérifie que le conteneur est actif et appartient à votre entreprise.' },
                { icon: 'PlusCircleIcon', text: 'Démarrez un nouveau lot ou consultez l\'historique des dépôts.' },
              ].map((step, i) => (
                <li key={i} className="flex items-start gap-3">
                  <div className="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 mt-0.5">
                    <span className="text-primary text-[11px] font-700">{i + 1}</span>
                  </div>
                  <p className="text-xs text-muted-foreground leading-relaxed">{step.text}</p>
                </li>
              ))}
            </ol>
          </div>

          <div className="bg-card rounded-xl border border-border p-5">
            <div className="flex items-center gap-2 mb-3">
              <Icon name="LightBulbIcon" size={16} className="text-amber-500" />
              <h3 className="text-sm font-600 text-foreground">Formats acceptés</h3>
            </div>
            <div className="space-y-2">
              {['QR-CT-001', 'QR-CT-042', 'CT-001'].map((code) => (
                <div key={code} className="flex items-center gap-2 px-3 py-1.5 bg-muted rounded-lg">
                  <Icon name="QrCodeIcon" size={12} className="text-muted-foreground" />
                  <span className="text-xs font-mono text-foreground">{code}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}