'use client';
import React from 'react';
import Link from 'next/link';
import Icon from '@/components/ui/AppIcon';

// Voir src/components/Sidebar.tsx pour le contexte complet du marqueur
// legacyLogisticsUI et du feature flag DEMO-only
// NEXT_PUBLIC_DEMO_HIDE_LEGACY_LOGISTICS_NAV (aucune suppression de page,
// route API ou composant — uniquement ces deux boutons d'action rapide du
// tableau de bord, qui menaient vers l'interface logistique legacy sans être
// couverts par le flag existant, contrairement aux entrées de menu
// équivalentes de Sidebar.tsx/MobileBottomNav.tsx — cf. #587).
const HIDE_LEGACY_LOGISTICS_UI = process.env.NEXT_PUBLIC_DEMO_HIDE_LEGACY_LOGISTICS_NAV === 'true';

export default function ClientQuickActions() {
  if (HIDE_LEGACY_LOGISTICS_UI) return null;

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