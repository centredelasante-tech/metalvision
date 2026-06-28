'use client';
import React, { useState } from 'react';
import { useRouter } from 'next/navigation';
import AppLogo from '@/components/ui/AppLogo';
import Icon from '@/components/ui/AppIcon';

interface TopbarProps {
  userRole: 'client' | 'admin';
}

const METAL_PRICES = [
  { metal: 'Fer', price: '0,27 $CA/kg', trend: 'up' },
  { metal: 'Cuivre', price: '10,90 $CA/kg', trend: 'up' },
  { metal: 'Aluminium', price: '2,72 $CA/kg', trend: 'down' },
  { metal: 'Acier', price: '0,35 $CA/kg', trend: 'neutral' },
];

export default function Topbar({ userRole }: TopbarProps) {
  const [notifOpen, setNotifOpen] = useState(false);
  const router = useRouter();

  const notifications = [
    { id: 'notif-1', text: 'Lot #LOT-0847 traité — 127,40 €', time: 'Il y a 12 min', type: 'success' },
    { id: 'notif-2', text: 'Conteneur CT-014 à 92% de capacité', time: 'Il y a 1h', type: 'warning' },
    { id: 'notif-3', text: 'Facture FAC-0234 envoyée', time: 'Il y a 3h', type: 'info' },
  ];

  return (
    <header className="h-14 md:h-16 bg-card border-b border-border flex items-center px-3 md:px-6 gap-3 flex-shrink-0 z-10">
      {/* Mobile: back button + logo */}
      <div className="flex lg:hidden items-center gap-2">
        <button
          onClick={() => router.back()}
          className="w-9 h-9 rounded-lg btn-ghost flex items-center justify-center text-muted-foreground"
          aria-label="Retour"
        >
          <Icon name="ChevronLeftIcon" size={20} />
        </button>
        <AppLogo size={26} />
        <span className="font-bold text-sm text-foreground">MetalVision</span>
      </div>

      {/* Metal price ticker — desktop */}
      <div className="hidden xl:flex items-center gap-4 flex-1">
        <div className="flex items-center gap-1 text-xs text-muted-foreground">
          <Icon name="ArrowTrendingUpIcon" size={14} />
          <span className="font-600 uppercase tracking-wide">Prix du jour</span>
        </div>
        {METAL_PRICES.map((mp) => (
          <div key={`ticker-${mp.metal}`} className="flex items-center gap-1.5">
            <span className="text-xs font-600 text-foreground">{mp.metal}</span>
            <span className="text-xs tabular-nums text-muted-foreground">{mp.price}</span>
            <Icon
              name={mp.trend === 'up' ? 'ArrowUpIcon' : mp.trend === 'down' ? 'ArrowDownIcon' : 'MinusIcon'}
              size={12}
              className={mp.trend === 'up' ? 'text-green-600' : mp.trend === 'down' ? 'text-red-500' : 'text-muted-foreground'}
            />
          </div>
        ))}
      </div>

      <div className="flex-1 lg:hidden" />

      {/* Right actions */}
      <div className="flex items-center gap-2 ml-auto">
        {/* Notifications */}
        <div className="relative">
          <button
            onClick={() => setNotifOpen(!notifOpen)}
            className="relative w-9 h-9 rounded-lg btn-ghost flex items-center justify-center"
            aria-label="Notifications"
          >
            <Icon name="BellIcon" size={20} className="text-muted-foreground" />
            <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-accent rounded-full" />
          </button>

          {notifOpen && (
            <div className="absolute right-0 top-12 w-[calc(100vw-2rem)] sm:w-80 bg-card border border-border rounded-xl shadow-modal z-50 overflow-hidden">
              <div className="flex items-center justify-between px-4 py-3 border-b border-border">
                <span className="text-sm font-600">Notifications</span>
                <span className="text-xs text-accent font-600 cursor-pointer">Tout marquer lu</span>
              </div>
              {notifications.map((n) => (
                <div key={n.id} className="flex items-start gap-3 px-4 py-3 row-hover border-b border-border last:border-0 cursor-pointer">
                  <div className={`w-2 h-2 rounded-full mt-1.5 flex-shrink-0 ${n.type === 'success' ? 'bg-primary' : n.type === 'warning' ? 'bg-accent' : 'bg-blue-500'}`} />
                  <div className="min-w-0">
                    <p className="text-sm text-foreground">{n.text}</p>
                    <p className="text-xs text-muted-foreground mt-0.5">{n.time}</p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Role badge — desktop only */}
        <div className="hidden sm:flex items-center gap-2 px-3 py-1.5 bg-muted rounded-lg">
          <div className="w-6 h-6 rounded-full bg-primary flex items-center justify-center">
            <span className="text-primary-foreground text-[10px] font-700">
              {userRole === 'admin' ? 'AD' : 'CL'}
            </span>
          </div>
          <span className="text-xs font-600 text-foreground">
            {userRole === 'admin' ? 'Administrateur' : 'Client'}
          </span>
        </div>
      </div>
    </header>
  );
}