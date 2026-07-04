'use client';
import React, { useState, useEffect } from 'react';
import Icon from '@/components/ui/AppIcon';
import { QRCodeSVG } from 'qrcode.react';

interface Container {
  id: string;
  qr_code: string;
  name: string;
  location: string | null;
  status: string;
  created_at: string;
  company_id: string;
}

interface ContainerQRCodeProps {
  container: Container;
}

export default function ContainerQRCode({ container }: ContainerQRCodeProps) {
  const [copied, setCopied] = useState(false);
  const [mounted, setMounted] = useState(false);
  const qrValue = `https://metaltrace.ca/container-detail/${container.id}`;

  useEffect(() => {
    setMounted(true);
  }, []);

  const handleCopy = () => {
    navigator.clipboard?.writeText(qrValue);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleDownload = () => {
    const svgEl = document.querySelector('#container-qr-svg svg') as SVGSVGElement | null;
    if (!svgEl) return;
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
      link.download = `qr-${container.qr_code}.png`;
      link.href = canvas.toDataURL('image/png');
      link.click();
    };
    img.src = `data:image/svg+xml;base64,${btoa(unescape(encodeURIComponent(svgData)))}`;
  };

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden">
      <div className="flex items-center justify-between px-5 py-4 border-b border-border">
        <div className="flex items-center gap-2">
          <Icon name="QrCodeIcon" size={16} className="text-primary" />
          <h3 className="text-sm font-600 text-foreground">QR Code conteneur</h3>
        </div>
        <div className="flex items-center gap-1.5">
          <button
            onClick={handleCopy}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-600 border border-border btn-ghost"
          >
            <Icon name={copied ? 'CheckIcon' : 'ClipboardDocumentIcon'} size={13} />
            {copied ? 'Copié !' : 'Copier'}
          </button>
          <button
            onClick={handleDownload}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-600 btn-primary"
          >
            <Icon name="ArrowDownTrayIcon" size={13} className="text-primary-foreground" />
            Télécharger
          </button>
        </div>
      </div>
      <div className="p-5 flex flex-col items-center gap-4">
        <div id="container-qr-svg" className="p-4 bg-white rounded-xl border border-border shadow-card">
          {mounted ? (
            <QRCodeSVG value={qrValue} size={140} />
          ) : (
            <div className="w-[140px] h-[140px] bg-gray-100 rounded animate-pulse" />
          )}
        </div>
        <div className="text-center">
          <p className="text-xs font-700 text-foreground tabular-nums">{container.name} · {container.qr_code}</p>
          <p className="text-[11px] text-muted-foreground mt-0.5 font-mono break-all">{qrValue}</p>
        </div>
        <div className="w-full p-3 bg-secondary rounded-lg flex items-center gap-2">
          <Icon name="InformationCircleIcon" size={14} className="text-primary flex-shrink-0" />
          <p className="text-xs text-primary">
            Imprimez et collez ce QR code sur le conteneur pour permettre le scan client.
          </p>
        </div>
      </div>
    </div>
  );
}