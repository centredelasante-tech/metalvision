'use client';
import React, { useState, useRef, useEffect, useCallback } from 'react';
import Icon from '@/components/ui/AppIcon';

type ScanState = 'idle' | 'scanning' | 'success' | 'error';

export default function QRScannerViewfinder() {
  const [scanState, setScanState] = useState<ScanState>('idle');
  const [torchOn, setTorchOn] = useState(false);
  const [detectedCode, setDetectedCode] = useState('');
  const [torchSupported, setTorchSupported] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const torchTrackRef = useRef<MediaStreamTrack | null>(null);

  const stopStream = useCallback(() => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }
    torchTrackRef.current = null;
  }, []);

  useEffect(() => {
    return () => stopStream();
  }, [stopStream]);

  const handleStartScan = async () => {
    setScanState('scanning');
    try {
      // Force environment (rear) camera, disable continuous autofocus on Android
      const constraints: MediaStreamConstraints = {
        video: {
          facingMode: { exact: 'environment' },
          width: { ideal: 1280 },
          height: { ideal: 720 },
          // @ts-ignore — advanced constraints for Android autofocus
          advanced: [{ focusMode: 'single-shot' }],
        },
      };

      let stream: MediaStream;
      try {
        stream = await navigator.mediaDevices.getUserMedia(constraints);
      } catch {
        // Fallback: try without exact constraint (some desktop browsers)
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: 'environment' },
        });
      }

      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        videoRef.current.play().catch(() => {});
      }

      // Check torch support
      const track = stream.getVideoTracks()[0];
      torchTrackRef.current = track;
      const capabilities = track.getCapabilities?.() as Record<string, unknown> | undefined;
      if (capabilities && 'torch' in capabilities) {
        setTorchSupported(true);
      }

      // Simulate QR detection after 3s (replace with jsQR in production)
      setTimeout(() => {
        setDetectedCode('CT-003-QR-8F2A4B');
        setScanState('success');
        stopStream();
      }, 3000);
    } catch {
      setScanState('error');
    }
  };

  const handleToggleTorch = async () => {
    if (!torchTrackRef.current) return;
    const newState = !torchOn;
    try {
      await torchTrackRef.current.applyConstraints({
        // @ts-ignore
        advanced: [{ torch: newState }],
      });
      setTorchOn(newState);
    } catch {
      // torch not supported on this device
    }
  };

  const handleReset = () => {
    stopStream();
    setScanState('idle');
    setDetectedCode('');
    setTorchOn(false);
    setTorchSupported(false);
  };

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="QrCodeIcon" size={18} className="text-primary" />
          <h2 className="text-base font-600 text-foreground">Lecteur QR code</h2>
        </div>
        <div className="flex items-center gap-2">
          {/* Flash / Torch button */}
          <button
            onClick={handleToggleTorch}
            disabled={!torchSupported && scanState !== 'scanning'}
            className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-sm font-600 border transition-all min-h-[40px] ${
              torchOn
                ? 'bg-accent text-accent-foreground border-amber-300'
                : 'bg-muted text-muted-foreground border-border btn-ghost'
            } ${!torchSupported ? 'opacity-50' : ''}`}
            title={torchSupported ? (torchOn ? 'Flash ON' : 'Flash OFF') : 'Flash non disponible'}
          >
            <Icon name="LightBulbIcon" size={16} />
            <span className="hidden sm:inline">{torchOn ? 'Flash ON' : 'Flash'}</span>
          </button>
        </div>
      </div>

      {/* Viewfinder */}
      <div className="relative bg-gray-900 w-full overflow-hidden" style={{ aspectRatio: '4/3' }}>
        {/* Live camera video */}
        <video
          ref={videoRef}
          autoPlay
          playsInline
          muted
          className={`absolute inset-0 w-full h-full object-cover ${scanState === 'scanning' ? 'block' : 'hidden'}`}
        />

        {/* Dark overlay with scan frame cutout */}
        {(scanState === 'idle' || scanState === 'scanning') && (
          <>
            {/* Semi-transparent overlay */}
            <div className="absolute inset-0 bg-black/50" />
            {/* Scan frame */}
            <div className="absolute inset-0 flex items-center justify-center">
              <div className="relative w-56 h-56 sm:w-64 sm:h-64">
                {/* Clear center */}
                <div className="absolute inset-0 bg-transparent border-0" />
                {/* Corner brackets */}
                <div className="absolute top-0 left-0 w-8 h-8 border-t-[3px] border-l-[3px] border-primary rounded-tl-lg" />
                <div className="absolute top-0 right-0 w-8 h-8 border-t-[3px] border-r-[3px] border-primary rounded-tr-lg" />
                <div className="absolute bottom-0 left-0 w-8 h-8 border-b-[3px] border-l-[3px] border-primary rounded-bl-lg" />
                <div className="absolute bottom-0 right-0 w-8 h-8 border-b-[3px] border-r-[3px] border-primary rounded-br-lg" />
                {/* Scan line */}
                {scanState === 'scanning' && (
                  <div className="absolute left-2 right-2 h-0.5 bg-primary opacity-80 scan-line-animate" />
                )}
              </div>
            </div>
          </>
        )}

        {/* Idle background */}
        {scanState === 'idle' && (
          <div className="absolute inset-0 bg-gradient-to-br from-gray-800 to-gray-950" />
        )}

        {/* Success state */}
        {scanState === 'success' && (
          <div className="absolute inset-0 bg-gray-900 flex items-center justify-center">
            <div className="w-20 h-20 bg-primary rounded-full flex items-center justify-center shadow-elevated fade-in-up">
              <Icon name="CheckIcon" size={36} className="text-primary-foreground" />
            </div>
          </div>
        )}

        {/* Error state */}
        {scanState === 'error' && (
          <div className="absolute inset-0 bg-gray-900 flex items-center justify-center">
            <div className="w-20 h-20 bg-red-500 rounded-full flex items-center justify-center fade-in-up">
              <Icon name="XMarkIcon" size={36} className="text-white" />
            </div>
          </div>
        )}

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
              <p className="text-white text-sm font-600">Caméra non disponible ou QR non reconnu</p>
              <p className="text-white/80 text-xs mt-0.5">Vérifiez les permissions caméra</p>
            </div>
          )}
        </div>
      </div>

      {/* Actions */}
      <div className="flex items-center gap-3 p-4">
        {scanState === 'idle' && (
          <button
            onClick={handleStartScan}
            className="flex-1 btn-primary py-3 rounded-lg text-base font-600 flex items-center justify-center gap-2 min-h-[48px]"
          >
            <Icon name="CameraIcon" size={20} className="text-primary-foreground" />
            Démarrer la caméra
          </button>
        )}
        {scanState === 'scanning' && (
          <button
            onClick={handleReset}
            className="flex-1 py-3 rounded-lg text-base font-600 border border-border text-foreground btn-ghost flex items-center justify-center gap-2 min-h-[48px]"
          >
            <Icon name="StopIcon" size={20} />
            Arrêter
          </button>
        )}
        {scanState === 'success' && (
          <>
            <a
              href="/container-detail"
              className="flex-1 btn-primary py-3 rounded-lg text-base font-600 flex items-center justify-center gap-2 min-h-[48px]"
            >
              <Icon name="ArrowRightIcon" size={20} className="text-primary-foreground" />
              Ouvrir le conteneur
            </a>
            <button
              onClick={handleReset}
              className="px-4 py-3 rounded-lg text-sm font-600 border border-border text-foreground btn-ghost min-h-[48px]"
            >
              Nouveau scan
            </button>
          </>
        )}
        {scanState === 'error' && (
          <button
            onClick={handleReset}
            className="flex-1 py-3 rounded-lg text-base font-600 btn-primary flex items-center justify-center gap-2 min-h-[48px]"
          >
            <Icon name="ArrowPathIcon" size={20} className="text-primary-foreground" />
            Réessayer
          </button>
        )}
      </div>
    </div>
  );
}