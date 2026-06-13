'use client';
import React from 'react';
import Link from 'next/link';
import Icon from '@/components/ui/AppIcon';

export default function ClientQuickActions() {
  return (
    <div className="flex items-center gap-3">
      <Link
        href="/qr-code-scanner"
        className="flex items-center gap-2 btn-primary px-4 py-2.5 rounded-lg text-sm font-600"
      >
        <Icon name="QrCodeIcon" size={16} className="text-primary-foreground" />
        Scanner un conteneur
      </Link>
      <Link
        href="/new-lot"
        className="flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600 border border-border bg-card text-foreground btn-ghost"
      >
        <Icon name="PlusIcon" size={16} />
        Nouveau lot
      </Link>
    </div>
  );
}