'use client';
import React, { useState } from 'react';
import Link from 'next/link';
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
  const [mobileOpen, setMobileOpen] = useState(false);
  const [notifOpen, setNotifOpen] = useState(false);

  const notifications = [
    { id: 'notif-1', text: 'Lot #LOT-0847 traité — 127,40 €', time: 'Il y a 12 min', type: 'success' },
    { id: 'notif-2', text: 'Conteneur CT-014 à 92% de capacité', time: 'Il y a 1h', type: 'warning' },
    { id: 'notif-3', text: 'Facture FAC-0234 envoyée', time: 'Il y a 3h', type: 'info' },
  ];

  return (
    <header className="h-16 bg-card border-b border-border flex items-center px-4 lg:px-6 gap-4 flex-shrink-0 z-10">
      {/* Mobile logo */}
      <div className="flex lg:hidden items-center gap-2">
        <AppLogo size={28} />
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
            <div className="absolute right-0 top-12 w-80 bg-card border border-border rounded-xl shadow-modal z-50 overflow-hidden">
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

        {/* Role badge */}
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

        {/* Mobile hamburger */}
        <button
          onClick={() => setMobileOpen(!mobileOpen)}
          className="lg:hidden w-9 h-9 rounded-lg btn-ghost flex items-center justify-center"
          aria-label="Menu"
        >
          <Icon name={mobileOpen ? 'XMarkIcon' : 'Bars3Icon'} size={20} />
        </button>
      </div>

      {/* Mobile drawer */}
      {mobileOpen && (
        <div className="absolute top-16 left-0 right-0 bg-card border-b border-border shadow-modal z-40 lg:hidden">
          <nav className="px-4 py-3 space-y-1">
            {[
              { label: 'Tableau de bord', href: userRole === 'admin' ? '/admin-dashboard' : '/', icon: 'HomeIcon' },
              { label: 'Scanner QR', href: '/qr-code-scanner', icon: 'QrCodeIcon' },
              { label: 'Nouveau lot', href: '/new-lot', icon: 'PlusCircleIcon' },
              { label: 'Conteneur', href: '/container-detail', icon: 'ArchiveBoxIcon' },
              ...(userRole === 'admin' ? [
                { label: 'Gestion lots', href: '/lot-management', icon: 'ClipboardDocumentListIcon' },
              ] : []),
            ].map((item) => (
              <Link
                key={`mobile-nav-${item.href}`}
                href={item.href}
                onClick={() => setMobileOpen(false)}
                className="flex items-center gap-3 px-3 py-2.5 rounded-lg sidebar-item text-sm font-medium"
              >
                <Icon name={item.icon as Parameters<typeof Icon>[0]['name']} size={18} />
                {item.label}
              </Link>
            ))}
          </nav>
        </div>
      )}
    </header>
  );
}