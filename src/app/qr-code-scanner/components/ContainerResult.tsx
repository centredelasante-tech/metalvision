'use client';
import React from 'react';
import Link from 'next/link';
import Icon from '@/components/ui/AppIcon';
import type { ContainerData } from './QRScannerContent';

interface ContainerResultProps {
  container: ContainerData | null;
  error: string | null;
  onReset: () => void;
}

export default function ContainerResult({ container, error, onReset }: ContainerResultProps) {
  if (error) {
    return (
      <div className="bg-card rounded-xl border border-red-200 dark:border-red-900 p-5">
        <div className="flex items-start gap-3">
          <div className="w-10 h-10 rounded-full bg-red-100 dark:bg-red-900/30 flex items-center justify-center flex-shrink-0">
            <Icon name="ExclamationTriangleIcon" size={20} className="text-red-600 dark:text-red-400" />
          </div>
          <div className="flex-1 min-w-0">
            <p className="text-sm font-600 text-red-700 dark:text-red-400">Conteneur introuvable</p>
            <p className="text-sm text-muted-foreground mt-1">{error}</p>
          </div>
        </div>
        <button
          onClick={onReset}
          className="mt-4 w-full py-2.5 rounded-lg border border-border text-sm font-600 text-foreground btn-ghost flex items-center justify-center gap-2"
        >
          <Icon name="ArrowPathIcon" size={16} />
          Réessayer
        </button>
      </div>
    );
  }

  if (!container) return null;

  return (
    <div className="bg-card rounded-xl border border-border overflow-hidden fade-in-up">
      {/* Success header */}
      <div className="flex items-center gap-3 px-5 py-4 bg-primary/5 border-b border-border">
        <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0">
          <Icon name="CheckCircleIcon" size={22} className="text-primary" />
        </div>
        <div>
          <p className="text-sm font-700 text-foreground">Conteneur identifié</p>
          <p className="text-xs text-muted-foreground font-mono">{container.qr_code}</p>
        </div>
      </div>

      {/* Container details */}
      <div className="px-5 py-4 space-y-3">
        <div className="grid grid-cols-2 gap-3">
          <div className="bg-muted rounded-lg px-4 py-3">
            <p className="text-[11px] text-muted-foreground uppercase tracking-wide font-600 mb-1">Nom</p>
            <p className="text-sm font-600 text-foreground truncate">{container.name}</p>
          </div>
          <div className="bg-muted rounded-lg px-4 py-3">
            <p className="text-[11px] text-muted-foreground uppercase tracking-wide font-600 mb-1">Statut</p>
            <div className="flex items-center gap-1.5">
              <div className="w-2 h-2 rounded-full bg-green-500" />
              <p className="text-sm font-600 text-green-700 dark:text-green-400 capitalize">{container.status}</p>
            </div>
          </div>
        </div>
        {container.location && (
          <div className="flex items-center gap-2 px-4 py-3 bg-muted rounded-lg">
            <Icon name="MapPinIcon" size={14} className="text-muted-foreground flex-shrink-0" />
            <p className="text-sm text-foreground">{container.location}</p>
          </div>
        )}
      </div>

      {/* Action buttons */}
      <div className="px-5 pb-5 flex flex-col sm:flex-row gap-3">
        <Link
          href={`/new-lot?container_id=${container.id}`}
          className="flex-1 btn-primary py-3 rounded-lg text-sm font-600 flex items-center justify-center gap-2 min-h-[44px]"
        >
          <Icon name="PlusCircleIcon" size={18} className="text-primary-foreground" />
          Démarrer un nouveau lot
        </Link>
        <Link
          href={`/container-detail?id=${container.id}`}
          className="flex-1 py-3 rounded-lg text-sm font-600 border border-border text-foreground btn-ghost flex items-center justify-center gap-2 min-h-[44px]"
        >
          <Icon name="ClockIcon" size={18} />
          Voir l'historique
        </Link>
      </div>

      <div className="px-5 pb-4">
        <button
          onClick={onReset}
          className="w-full py-2 rounded-lg text-xs font-600 text-muted-foreground hover:text-foreground transition-colors flex items-center justify-center gap-1.5"
        >
          <Icon name="ArrowPathIcon" size={14} />
          Scanner un autre conteneur
        </button>
      </div>
    </div>
  );
}
