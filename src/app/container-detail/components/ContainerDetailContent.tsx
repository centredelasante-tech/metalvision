'use client';
import React from 'react';
import ContainerHeader from './ContainerHeader';
import ContainerInfoPanel from './ContainerInfoPanel';
import ContainerQRCode from './ContainerQRCode';
import ContainerLotHistory from './ContainerLotHistory';
import Icon from '@/components/ui/AppIcon';
import Link from 'next/link';

interface Container {
  id: string;
  qr_code: string;
  name: string;
  location: string | null;
  status: string;
  created_at: string;
  company_id: string;
}

interface ContainerDetailContentProps {
  container: Container | null;
}

export default function ContainerDetailContent({ container }: ContainerDetailContentProps) {
  if (!container) {
    return (
      <div className="flex flex-col items-center justify-center py-24 gap-4">
        <div className="w-16 h-16 rounded-2xl bg-secondary flex items-center justify-center">
          <Icon name="ArchiveBoxXMarkIcon" size={32} className="text-muted-foreground" />
        </div>
        <div className="text-center">
          <h2 className="text-xl font-700 text-foreground">Conteneur introuvable</h2>
          <p className="text-sm text-muted-foreground mt-1">
            L&apos;identifiant fourni ne correspond à aucun conteneur.
          </p>
        </div>
        <Link
          href="/lot-management"
          className="flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600 btn-primary"
        >
          <Icon name="ArrowLeftIcon" size={16} className="text-primary-foreground" />
          Retour à la gestion des lots
        </Link>
      </div>
    );
  }

  return (
    <div className="space-y-4 md:space-y-6">
      <ContainerHeader container={container} />

      <div className="flex flex-col xl:grid xl:grid-cols-3 gap-4 md:gap-6">
        {/* Left column */}
        <div className="space-y-4 md:space-y-5">
          <ContainerInfoPanel container={container} />
          {/* QR code max 200x200 on mobile */}
          <div className="max-w-[200px] mx-auto xl:max-w-none">
            <ContainerQRCode container={container} />
          </div>
        </div>

        {/* Right columns */}
        <div className="xl:col-span-2 space-y-4 md:space-y-5">
          <ContainerLotHistory containerId={container.id} />
        </div>
      </div>
    </div>
  );
}