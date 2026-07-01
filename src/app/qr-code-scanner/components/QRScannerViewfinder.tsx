'use client';
import React, { useState, useRef, useEffect, useCallback } from 'react';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import type { ContainerData } from './QRScannerContent';

type ScanState = 'idle' | 'scanning' | 'processing' | 'done' | 'error';

interface QRScannerViewfinderProps {
  onResult: (container: ContainerData | null, error: string | null) => void;
}

export default function QRScannerViewfinder({ onResult }: QRScannerViewfinderProps) {
  const { user } = useAuth();
  const [scanState, setScanState] = useState<ScanState>('idle');
  const [torchOn, setTorchOn] = useState(false);
  const [torchSupported, setTorchSupported] = useState(false);
  const [cameraError, setCameraError] = useState<string | null>(null);

  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const torchTrackRef = useRef<MediaStreamTrack | null>(null);
  const rafRef = useRef<number | null>(null);
  const processingRef = useRef(false);

  const stopStream = useCallback(() => {
    if (rafRef.current) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = null;
    }
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop());
      streamRef.current = null;
    }
    torchTrackRef.current = null;
    processingRef.current = false;
  }, []);

  useEffect(() => {
    return () => stopStream();
  }, [stopStream]);

  const lookupContainer = useCallback(async (qrCode: string) => {
    if (processingRef.current) return;
    processingRef.current = true;
    setScanState('processing');
    stopStream();

    const supabase = createClient();

    // Get user's company_id
    const { data: memberData } = await supabase
      .from('company_members')
      .select('company_id')
      .eq('user_id', user?.id)
      .limit(1)
      .single();

    const userCompanyId = memberData?.company_id ?? null;

    // Query container by qr_code
    const { data: containers, error } = await supabase
      .from('containers')
      .select('id, name, location, status, company_id, qr_code')
      .eq('qr_code', qrCode)
      .eq('status', 'active')
      .limit(1);

    if (error || !containers || containers.length === 0) {
      onResult(null, 'Conteneur introuvable ou inactif. Vérifiez le code et réessayez.');
      setScanState('done');
      return;
    }

    const container = containers[0] as ContainerData;

    if (userCompanyId && container.company_id !== userCompanyId) {
      onResult(null, 'Ce conteneur appartient à une autre entreprise. Vous n\'êtes pas autorisé à y accéder.');
      setScanState('done');
      return;
    }

    // --- GPS + scan_event insertion (non-blocking, 12s total cap) ---
    const getGPS = (): Promise<{ gps_lat: number | null; gps_lng: number | null; gps_accuracy_m: number | null }> =>
      new Promise((resolve) => {
        if (typeof navigator === 'undefined' || !navigator.geolocation) {
          resolve({ gps_lat: null, gps_lng: null, gps_accuracy_m: null });
          return;
        }
        navigator.geolocation.getCurrentPosition(
          (pos) => resolve({
            gps_lat: pos.coords.latitude,
            gps_lng: pos.coords.longitude,
            gps_accuracy_m: pos.coords.accuracy ?? null,
          }),
          () => resolve({ gps_lat: null, gps_lng: null, gps_accuracy_m: null }),
          { timeout: 10000, maximumAge: 30000, enableHighAccuracy: false }
        );
      });

    const insertScanEvent = async () => {
      const gpsPromise = getGPS();
      const { gps_lat, gps_lng, gps_accuracy_m } = await gpsPromise;

      const { error: insertError } = await supabase
        .from('scan_events')
        .insert({
          container_id: container.id,
          company_id: container.company_id,
          user_id: user?.id,
          action_type: 'collecte',
          gps_lat,
          gps_lng,
          gps_accuracy_m,
          scanned_at: new Date().toISOString(),
        });

      if (insertError) {
        console.warn('[scan_event] Insertion failed:', insertError);
      }
    };

    const timeoutPromise = new Promise<void>((resolve) => setTimeout(resolve, 12000));

    await Promise.race([insertScanEvent(), timeoutPromise]);
    // --- end scan_event ---

    onResult(container, null);
    setScanState('done');
  }, [user, onResult, stopStream]);

  const tickScan = useCallback(() => {
    const video = videoRef.current;
    const canvas = canvasRef.current;
    if (!video || !canvas || video.readyState !== video.HAVE_ENOUGH_DATA) {
      rafRef.current = requestAnimationFrame(tickScan);
      return;
    }

    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext('2d');
    if (!ctx) {
      rafRef.current = requestAnimationFrame(tickScan);
      return;
    }

    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
    const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);

    // Dynamic import of jsQR to avoid SSR issues
    import('jsqr').then(({ default: jsQR }) => {
      const code = jsQR(imageData.data, imageData.width, imageData.height, {
        inversionAttempts: 'dontInvert',
      });
      if (code?.data) {
        lookupContainer(code.data);
      } else {
        rafRef.current = requestAnimationFrame(tickScan);
      }
    });
  }, [lookupContainer]);

  const handleStartScan = async () => {
    setCameraError(null);
    setScanState('scanning');
    processingRef.current = false;

    try {
      let stream: MediaStream;
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { exact: 'environment' }, width: { ideal: 1280 }, height: { ideal: 720 } },
        });
      } catch {
        stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
      }

      streamRef.current = stream;
      if (videoRef.current) {
        videoRef.current.srcObject = stream;
        await videoRef.current.play().catch(() => {});
      }

      const track = stream.getVideoTracks()[0];
      torchTrackRef.current = track;
      const capabilities = track.getCapabilities?.() as Record<string, unknown> | undefined;
      if (capabilities && 'torch' in capabilities) setTorchSupported(true);

      rafRef.current = requestAnimationFrame(tickScan);
    } catch {
      setScanState('error');
      setCameraError('Impossible d\'accéder à la caméra. Vérifiez les permissions.');
    }
  };

  const handleToggleTorch = async () => {
    if (!torchTrackRef.current) return;
    const next = !torchOn;
    try {
      await torchTrackRef.current.applyConstraints({ advanced: [{ torch: next } as MediaTrackConstraintSet] });
      setTorchOn(next);
    } catch { /* torch not supported */ }
  };

  const handleReset = () => {
    stopStream();
    setScanState('idle');
    setTorchOn(false);
    setTorchSupported(false);
    setCameraError(null);
  };

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="QrCodeIcon" size={18} className="text-primary" />
          <h2 className="text-base font-600 text-foreground">Lecteur QR code</h2>
        </div>
        {torchSupported && scanState === 'scanning' && (
          <button
            onClick={handleToggleTorch}
            className={`flex items-center gap-1.5 px-3 py-2 rounded-lg text-sm font-600 border transition-all min-h-[40px] ${
              torchOn
                ? 'bg-amber-100 text-amber-700 border-amber-300 dark:bg-amber-900/30 dark:text-amber-400' :'bg-muted text-muted-foreground border-border btn-ghost'
            }`}
          >
            <Icon name="LightBulbIcon" size={16} />
            <span className="hidden sm:inline">{torchOn ? 'Flash ON' : 'Flash'}</span>
          </button>
        )}
      </div>

      {/* Viewfinder */}
      <div className="relative bg-gray-900 w-full overflow-hidden" style={{ aspectRatio: '4/3' }}>
        <video
          ref={videoRef}
          autoPlay
          playsInline
          muted
          className={`absolute inset-0 w-full h-full object-cover ${scanState === 'scanning' ? 'block' : 'hidden'}`}
        />
        <canvas ref={canvasRef} className="hidden" />

        {/* Overlay with scan frame */}
        {(scanState === 'idle' || scanState === 'scanning') && (
          <>
            <div className="absolute inset-0 bg-black/50" />
            <div className="absolute inset-0 flex items-center justify-center">
              <div className="relative w-56 h-56 sm:w-64 sm:h-64">
                <div className="absolute top-0 left-0 w-8 h-8 border-t-[3px] border-l-[3px] border-primary rounded-tl-lg" />
                <div className="absolute top-0 right-0 w-8 h-8 border-t-[3px] border-r-[3px] border-primary rounded-tr-lg" />
                <div className="absolute bottom-0 left-0 w-8 h-8 border-b-[3px] border-l-[3px] border-primary rounded-bl-lg" />
                <div className="absolute bottom-0 right-0 w-8 h-8 border-b-[3px] border-r-[3px] border-primary rounded-br-lg" />
                {scanState === 'scanning' && (
                  <div className="absolute left-2 right-2 h-0.5 bg-primary opacity-80 scan-line-animate" />
                )}
              </div>
            </div>
          </>
        )}

        {/* Idle bg */}
        {scanState === 'idle' && (
          <div className="absolute inset-0 bg-gradient-to-br from-gray-800 to-gray-950" />
        )}

        {/* Processing */}
        {scanState === 'processing' && (
          <div className="absolute inset-0 bg-gray-900 flex flex-col items-center justify-center gap-3">
            <div className="w-12 h-12 border-4 border-primary/30 border-t-primary rounded-full animate-spin" />
            <p className="text-white/80 text-sm">Vérification en cours…</p>
          </div>
        )}

        {/* Done */}
        {scanState === 'done' && (
          <div className="absolute inset-0 bg-gray-900 flex items-center justify-center">
            <div className="w-20 h-20 bg-primary rounded-full flex items-center justify-center shadow-elevated fade-in-up">
              <Icon name="CheckIcon" size={36} className="text-primary-foreground" />
            </div>
          </div>
        )}

        {/* Camera error */}
        {scanState === 'error' && (
          <div className="absolute inset-0 bg-gray-900 flex items-center justify-center p-6">
            <div className="text-center">
              <div className="w-16 h-16 bg-red-500 rounded-full flex items-center justify-center mx-auto mb-3 fade-in-up">
                <Icon name="XMarkIcon" size={28} className="text-white" />
              </div>
              <p className="text-white text-sm font-600">{cameraError}</p>
            </div>
          </div>
        )}

        {/* Status bar */}
        <div className="absolute bottom-0 left-0 right-0 p-4">
          {scanState === 'idle' && (
            <p className="text-white/70 text-sm text-center">Appuyez sur "Démarrer" pour activer la caméra</p>
          )}
          {scanState === 'scanning' && (
            <div className="flex items-center justify-center gap-2">
              <div className="w-2 h-2 bg-primary rounded-full animate-pulse" />
              <p className="text-white text-sm">Recherche d'un QR code…</p>
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
        {(scanState === 'done' || scanState === 'error') && (
          <button
            onClick={handleReset}
            className="flex-1 py-3 rounded-lg text-base font-600 border border-border text-foreground btn-ghost flex items-center justify-center gap-2 min-h-[48px]"
          >
            <Icon name="ArrowPathIcon" size={20} />
            Nouveau scan
          </button>
        )}
      </div>
    </div>
  );
}