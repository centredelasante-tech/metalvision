'use client';
import React, { useEffect, useRef, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import Icon from '@/components/ui/AppIcon';

interface QRCodeModalProps {
  containerId: string;
  containerName: string;
  containerQrCode: string;
  onClose: () => void;
}

export default function QRCodeModal({ containerId, containerName, containerQrCode, onClose }: QRCodeModalProps) {
  const [origin, setOrigin] = useState('');
  const svgWrapperRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setOrigin(window.location.origin);
  }, []);

  const qrCodeUrl = origin ? `${origin}/container-detail/${containerId}` : '';

  const handleDownload = () => {
    const svgEl = svgWrapperRef.current?.querySelector('svg') as SVGSVGElement | null;
    if (!svgEl || !qrCodeUrl) return;
    const canvas = document.createElement('canvas');
    canvas.width = 256;
    canvas.height = 256;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const svgData = new XMLSerializer().serializeToString(svgEl);
    const img = new Image();
    img.onload = () => {
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, 256, 256);
      ctx.drawImage(img, 0, 0, 256, 256);
      const link = document.createElement('a');
      link.download = `qr-${containerQrCode}.png`;
      link.href = canvas.toDataURL('image/png');
      link.click();
    };
    img.src = `data:image/svg+xml;base64,${btoa(unescape(encodeURIComponent(svgData)))}`;
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-card rounded-2xl border border-border shadow-xl w-full max-w-sm overflow-hidden">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-border">
          <div className="flex items-center gap-2">
            <Icon name="QrCodeIcon" size={18} className="text-primary" />
            <h2 className="text-base font-700 text-foreground">QR Code conteneur</h2>
          </div>
          <button
            onClick={onClose}
            className="w-8 h-8 rounded-lg btn-ghost flex items-center justify-center text-muted-foreground"
          >
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>

        {/* Body */}
        <div className="p-6 flex flex-col items-center gap-4">
          <div className="text-center mb-1">
            <p className="text-sm font-700 text-foreground">{containerName}</p>
            <p className="text-xs text-muted-foreground font-mono mt-0.5">{containerQrCode}</p>
          </div>

          <div ref={svgWrapperRef} className="p-4 bg-white rounded-xl border border-border shadow-card">
            {qrCodeUrl ? (
              <QRCodeSVG value={qrCodeUrl} size={256} />
            ) : (
              <div className="w-[256px] h-[256px] bg-gray-100 rounded animate-pulse" />
            )}
          </div>

          <p className="text-[11px] text-muted-foreground font-mono text-center break-all px-2">
            {qrCodeUrl}
          </p>
        </div>

        {/* Footer */}
        <div className="flex gap-3 px-5 py-4 border-t border-border">
          <button
            onClick={onClose}
            className="flex-1 py-2.5 rounded-lg text-sm font-600 border border-border btn-ghost"
          >
            Fermer
          </button>
          <button
            onClick={handleDownload}
            disabled={!qrCodeUrl}
            className="flex-1 py-2.5 rounded-lg text-sm font-600 btn-primary flex items-center justify-center gap-2 disabled:opacity-50"
          >
            <Icon name="ArrowDownTrayIcon" size={16} className="text-primary-foreground" />
            Télécharger PNG
          </button>
        </div>
      </div>
    </div>
  );
}
