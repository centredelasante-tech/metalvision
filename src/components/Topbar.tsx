'use client';
import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import AppLogo from '@/components/ui/AppLogo';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';

interface TopbarProps {
  userRole: 'client' | 'admin';
}

interface MetalPrice {
  label: string;
  price: number | null;
  trend: 'up' | 'down' | 'neutral';
  available: boolean;
}

interface Notification {
  id: string;
  text: string;
  time: string;
  type: 'success' | 'warning' | 'info';
}

function getRelativeTime(dateStr: string): string {
  const now = Date.now();
  const then = new Date(dateStr).getTime();
  const diffMs = now - then;
  const diffMin = Math.floor(diffMs / 60000);
  if (diffMin < 1) return 'À l\'instant';
  if (diffMin < 60) return `Il y a ${diffMin} min`;
  const diffH = Math.floor(diffMin / 60);
  if (diffH < 24) return `Il y a ${diffH}h`;
  const diffD = Math.floor(diffH / 24);
  return `Il y a ${diffD}j`;
}

function buildNotificationText(row: {
  status: string;
  official_metal_type: string | null;
  metal_type_predicted: string | null;
  weight_kg: number | null;
  official_weight_kg: number | null;
  price_paid: number | null;
}): { text: string; type: 'success' | 'warning' | 'info' } {
  const metal = row.official_metal_type ?? row.metal_type_predicted ?? 'Métal';
  const weight = row.official_weight_kg ?? row.weight_kg;
  const weightStr = weight != null ? ` — ${Number(weight).toFixed(1)} kg` : '';

  if (row.status === 'invoiced') {
    const priceStr = row.price_paid != null ? ` — ${Number(row.price_paid).toFixed(2)} $CA` : '';
    return { text: `Mesure ${metal} facturée${weightStr}${priceStr}`, type: 'success' };
  }
  if (row.status === 'processed') {
    return { text: `Mesure ${metal} traitée${weightStr}`, type: 'info' };
  }
  // submitted
  return { text: `Nouvelle mesure ${metal} soumise${weightStr}`, type: 'warning' };
}

export default function Topbar({ userRole }: TopbarProps) {
  const [notifOpen, setNotifOpen] = useState(false);
  const [metalPrices, setMetalPrices] = useState<MetalPrice[]>([]);
  const [pricesLoading, setPricesLoading] = useState(true);
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [notifLoading, setNotifLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    let cancelled = false;
    async function fetchPrices() {
      try {
        const res = await fetch('/api/metals-price');
        if (!res.ok) throw new Error('fetch failed');
        const data = await res.json();
        if (!cancelled && Array.isArray(data.metals)) {
          setMetalPrices(data.metals);
        }
      } catch {
        // silently fail — ticker stays empty
      } finally {
        if (!cancelled) setPricesLoading(false);
      }
    }
    fetchPrices();
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    let cancelled = false;
    async function fetchNotifications() {
      try {
        const supabase = createClient();
        const { data, error } = await supabase
          .from('raw_measurements')
          .select('id, status, official_metal_type, metal_type_predicted, weight_kg, official_weight_kg, price_paid, created_at')
          .order('created_at', { ascending: false })
          .limit(5);

        if (!cancelled) {
          if (error || !data || data.length === 0) {
            setNotifications([]);
          } else {
            const built: Notification[] = data.map((row) => {
              const { text, type } = buildNotificationText(row);
              return {
                id: row.id,
                text,
                time: getRelativeTime(row.created_at),
                type,
              };
            });
            setNotifications(built);
          }
        }
      } catch {
        if (!cancelled) setNotifications([]);
      } finally {
        if (!cancelled) setNotifLoading(false);
      }
    }
    fetchNotifications();
    return () => { cancelled = true; };
  }, []);

  function formatPrice(price: number | null, available: boolean): string {
    if (!available || price === null) return 'N/D';
    return `${price.toFixed(2)} $CA/kg`;
  }

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
        <span className="font-bold text-sm text-foreground">METALTRACE</span>
      </div>

      {/* Metal price ticker — desktop */}
      <div className="hidden xl:flex items-center gap-4 flex-1">
        <div className="flex items-center gap-1 text-xs text-muted-foreground">
          <Icon name="ArrowTrendingUpIcon" size={14} />
          <span className="font-600 uppercase tracking-wide">Prix du jour</span>
        </div>
        {pricesLoading ? (
          <span className="text-xs text-muted-foreground">...</span>
        ) : (
          metalPrices.map((mp) => (
            <div key={`ticker-${mp.label}`} className="flex items-center gap-1.5">
              <span className="text-xs font-600 text-foreground">{mp.label}</span>
              <span className="text-xs tabular-nums text-muted-foreground">{formatPrice(mp.price, mp.available)}</span>
              {mp.available && (
                <Icon
                  name={mp.trend === 'up' ? 'ArrowUpIcon' : mp.trend === 'down' ? 'ArrowDownIcon' : 'MinusIcon'}
                  size={12}
                  className={mp.trend === 'up' ? 'text-green-600' : mp.trend === 'down' ? 'text-red-500' : 'text-muted-foreground'}
                />
              )}
            </div>
          ))
        )}
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
            {notifications.length > 0 && (
              <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-accent rounded-full" />
            )}
          </button>

          {notifOpen && (
            <div className="absolute right-0 top-12 w-[calc(100vw-2rem)] sm:w-80 bg-card border border-border rounded-xl shadow-modal z-50 overflow-hidden">
              <div className="flex items-center justify-between px-4 py-3 border-b border-border">
                <span className="text-sm font-600">Notifications</span>
                {notifications.length > 0 && (
                  <span className="text-xs text-accent font-600 cursor-pointer">Tout marquer lu</span>
                )}
              </div>
              {notifLoading ? (
                <div className="px-4 py-6 text-center text-xs text-muted-foreground">Chargement...</div>
              ) : notifications.length === 0 ? (
                <div className="px-4 py-6 text-center text-xs text-muted-foreground">Aucune notification récente</div>
              ) : (
                notifications.map((n) => (
                  <div key={n.id} className="flex items-start gap-3 px-4 py-3 row-hover border-b border-border last:border-0 cursor-pointer">
                    <div className={`w-2 h-2 rounded-full mt-1.5 flex-shrink-0 ${n.type === 'success' ? 'bg-primary' : n.type === 'warning' ? 'bg-accent' : 'bg-blue-500'}`} />
                    <div className="min-w-0">
                      <p className="text-sm text-foreground">{n.text}</p>
                      <p className="text-xs text-muted-foreground mt-0.5">{n.time}</p>
                    </div>
                  </div>
                ))
              )}
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

        {/* Logout button */}
        <button
          onClick={async () => {
            const supabase = createClient();
            await supabase.auth.signOut();
            router.push('/login');
          }}
          className="flex items-center gap-1.5 px-2 sm:px-3 py-1.5 rounded-lg btn-ghost text-muted-foreground hover:text-foreground"
          aria-label="Déconnexion"
        >
          <Icon name="ArrowRightOnRectangleIcon" size={18} />
          <span className="hidden sm:inline text-xs font-600">Déconnexion</span>
        </button>
      </div>
    </header>
  );
}