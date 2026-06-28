'use client';
import React, { useState, useEffect } from 'react';
import Icon from '@/components/ui/AppIcon';

function QRCodePlaceholder({ value }: { value: string }) {
  // Simple visual QR code placeholder using CSS grid pattern
  // BACKEND INTEGRATION: Replace with actual QR code library when needed
  const seed = value.split('').reduce((acc, c) => acc + c.charCodeAt(0), 0);
  const size = 10;
  const cells = Array.from({ length: size * size }, (_, i) => {
    const x = i % size;
    const y = Math.floor(i / size);
    // Always fill corners (finder patterns)
    const inTopLeft = x < 3 && y < 3;
    const inTopRight = x >= size - 3 && y < 3;
    const inBottomLeft = x < 3 && y >= size - 3;
    if (inTopLeft || inTopRight || inBottomLeft) return true;
    // Pseudo-random fill for data area
    return ((seed * (i + 1) * 31) % 97) > 48;
  });

  return (
    <div
      className="grid bg-white p-1"
      style={{ gridTemplateColumns: `repeat(${size}, 1fr)`, width: 140, height: 140 }}
      aria-label={`QR Code: ${value}`}
    >
      {cells.map((filled, i) => (
        <div
          key={`qr-cell-${i}`}
          className={filled ? 'bg-gray-900' : 'bg-white'}
        />
      ))}
    </div>
  );
}

export default function ContainerQRCode() {
  const [copied, setCopied] = useState(false);
  const [mounted, setMounted] = useState(false);
  const qrValue = 'https://metaltrace.ca/c/CT-003';

  useEffect(() => {
    setMounted(true);
  }, []);

  const handleCopy = () => {
    navigator.clipboard?.writeText(qrValue);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
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
          <button className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-xs font-600 btn-primary">
            <Icon name="ArrowDownTrayIcon" size={13} className="text-primary-foreground" />
            Télécharger
          </button>
        </div>
      </div>
      <div className="p-5 flex flex-col items-center gap-4">
        <div className="p-4 bg-white rounded-xl border border-border shadow-card">
          {mounted ? (
            <QRCodePlaceholder value={qrValue} />
          ) : (
            <div className="w-[140px] h-[140px] bg-gray-100 rounded animate-pulse" />
          )}
        </div>
        <div className="text-center">
          <p className="text-xs font-700 text-foreground tabular-nums">CT-003</p>
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