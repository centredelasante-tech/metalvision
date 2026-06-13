'use client';
import React, { useState } from 'react';
import Icon from '@/components/ui/AppIcon';

export default function ContainerHeader() {
  const [editing, setEditing] = useState(false);

  return (
    <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
      <div className="flex items-center gap-4">
        <div className="w-14 h-14 rounded-2xl bg-secondary flex items-center justify-center flex-shrink-0">
          <Icon name="ArchiveBoxIcon" size={28} className="text-primary" />
        </div>
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-2xl font-700 text-foreground">CT-003</h1>
            <span className="inline-flex items-center gap-1.5 px-2.5 py-1 bg-red-100 text-red-600 rounded-full text-xs font-600">
              <div className="w-1.5 h-1.5 bg-red-500 rounded-full animate-pulse" />
              Capacité critique
            </span>
          </div>
          <p className="text-sm text-muted-foreground mt-0.5">
            Zone C — Stockage · Acier Industrie SA · Capteur ultrason connecté
          </p>
        </div>
      </div>

      <div className="flex items-center gap-2">
        <button
          onClick={() => setEditing(!editing)}
          className="flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600 border border-border text-foreground btn-ghost"
        >
          <Icon name="PencilSquareIcon" size={16} />
          Modifier
        </button>
        <button className="flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600 btn-primary">
          <Icon name="PlusCircleIcon" size={16} className="text-primary-foreground" />
          Nouveau lot
        </button>
        <button className="w-10 h-10 rounded-lg border border-border text-muted-foreground btn-ghost flex items-center justify-center">
          <Icon name="EllipsisVerticalIcon" size={18} />
        </button>
      </div>
    </div>
  );
}