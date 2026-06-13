'use client';
import React, { useState } from 'react';
import Icon from '@/components/ui/AppIcon';

type ScanState = 'idle' | 'scanning' | 'success' | 'error';

export default function QRScannerViewfinder() {
  const [scanState, setScanState] = useState<ScanState>('idle');
  const [torchOn, setTorchOn] = useState(false);
  const [detectedCode, setDetectedCode] = useState('');

  const handleStartScan = () => {
    setScanState('scanning');
    // BACKEND INTEGRATION: Initialize camera stream and QR decoder here
    // Use jsQR or ZXing to decode frames from <video> element
    setTimeout(() => {
      setDetectedCode('CT-003-QR-8F2A4B');
      setScanState('success');
    }, 3000);
  };

  const handleReset = () => {
    setScanState('idle');
    setDetectedCode('');
  };

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="QrCodeIcon" size={18} className="text-primary" />
          <h2 className="text-sm font-600 text-foreground">Lecteur QR code</h2>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setTorchOn(!torchOn)}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-600 border transition-all ${
              torchOn
                ? 'bg-accent text-accent-foreground border-amber-300'
                : 'bg-muted text-muted-foreground border-border btn-ghost'
            }`}
          >
            <Icon name="LightBulbIcon" size={14} />
            {torchOn ? 'Torche ON' : 'Torche'}
          </button>
          <button
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-600 border border-border bg-muted text-muted-foreground btn-ghost"
          >
            <Icon name="ArrowPathIcon" size={14} />
            Inverser
          </button>
        </div>
      </div>

      {/* Viewfinder */}
      <div className="relative bg-gray-900 aspect-[4/3] w-full flex items-center justify-center overflow-hidden">
        {/* Simulated camera feed background */}
        <div className="absolute inset-0 bg-gradient-to-br from-gray-800 to-gray-950 opacity-90" />

        {/* Corner decorations */}
        <div className="absolute top-8 left-1/2 -translate-x-1/2 w-56 h-56">
          {/* Scan frame */}
          {(scanState === 'idle' || scanState === 'scanning') && (
            <>
              {/* Corners */}
              <div className="absolute top-0 left-0 w-8 h-8 border-t-3 border-l-3 border-primary rounded-tl-lg" style={{ borderTopWidth: 3, borderLeftWidth: 3 }} />
              <div className="absolute top-0 right-0 w-8 h-8 border-t-3 border-r-3 border-primary rounded-tr-lg" style={{ borderTopWidth: 3, borderRightWidth: 3 }} />
              <div className="absolute bottom-0 left-0 w-8 h-8 border-b-3 border-l-3 border-primary rounded-bl-lg" style={{ borderBottomWidth: 3, borderLeftWidth: 3 }} />
              <div className="absolute bottom-0 right-0 w-8 h-8 border-b-3 border-r-3 border-primary rounded-br-lg" style={{ borderBottomWidth: 3, borderRightWidth: 3 }} />

              {/* Scan line */}
              {scanState === 'scanning' && (
                <div className="absolute left-2 right-2 h-0.5 bg-primary opacity-80 scan-line-animate" />
              )}
            </>
          )}

          {/* Success state */}
          {scanState === 'success' && (
            <div className="absolute inset-0 flex items-center justify-center">
              <div className="w-16 h-16 bg-primary rounded-full flex items-center justify-center shadow-elevated fade-in-up">
                <Icon name="CheckIcon" size={32} className="text-primary-foreground" />
              </div>
            </div>
          )}

          {/* Error state */}
          {scanState === 'error' && (
            <div className="absolute inset-0 flex items-center justify-center">
              <div className="w-16 h-16 bg-red-500 rounded-full flex items-center justify-center fade-in-up">
                <Icon name="XMarkIcon" size={32} className="text-white" />
              </div>
            </div>
          )}
        </div>

        {/* Status overlay bottom */}
        <div className="absolute bottom-0 left-0 right-0 p-4">
          {scanState === 'idle' && (
            <p className="text-white/70 text-sm text-center">
              Appuyez sur "Démarrer" pour activer la caméra
            </p>
          )}
          {scanState === 'scanning' && (
            <div className="flex items-center justify-center gap-2">
              <div className="w-2 h-2 bg-primary rounded-full animate-pulse" />
              <p className="text-white text-sm">Recherche d'un QR code...</p>
            </div>
          )}
          {scanState === 'success' && (
            <div className="bg-primary/90 rounded-lg px-4 py-2 text-center fade-in-up">
              <p className="text-primary-foreground text-sm font-600">QR code détecté !</p>
              <p className="text-primary-foreground/80 text-xs tabular-nums mt-0.5">{detectedCode}</p>
            </div>
          )}
          {scanState === 'error' && (
            <div className="bg-red-500/90 rounded-lg px-4 py-2 text-center">
              <p className="text-white text-sm font-600">QR code non reconnu</p>
              <p className="text-white/80 text-xs mt-0.5">Vérifiez que le conteneur est enregistré</p>
            </div>
          )}
        </div>
      </div>

      {/* Actions */}
      <div className="flex items-center gap-3 p-5">
        {scanState === 'idle' && (
          <button
            onClick={handleStartScan}
            className="flex-1 btn-primary py-3 rounded-lg text-sm font-600 flex items-center justify-center gap-2"
          >
            <Icon name="CameraIcon" size={18} className="text-primary-foreground" />
            Démarrer la caméra
          </button>
        )}
        {scanState === 'scanning' && (
          <button
            onClick={handleReset}
            className="flex-1 py-3 rounded-lg text-sm font-600 border border-border text-foreground btn-ghost flex items-center justify-center gap-2"
          >
            <Icon name="StopIcon" size={18} />
            Arrêter
          </button>
        )}
        {scanState === 'success' && (
          <>
            <a
              href="/container-detail"
              className="flex-1 btn-primary py-3 rounded-lg text-sm font-600 flex items-center justify-center gap-2"
            >
              <Icon name="ArrowRightIcon" size={18} className="text-primary-foreground" />
              Ouvrir le conteneur
            </a>
            <button
              onClick={handleReset}
              className="px-4 py-3 rounded-lg text-sm font-600 border border-border text-foreground btn-ghost"
            >
              Nouveau scan
            </button>
          </>
        )}
        {scanState === 'error' && (
          <button
            onClick={handleReset}
            className="flex-1 py-3 rounded-lg text-sm font-600 btn-primary flex items-center justify-center gap-2"
          >
            <Icon name="ArrowPathIcon" size={18} className="text-primary-foreground" />
            Réessayer
          </button>
        )}
      </div>
    </div>
  );
}