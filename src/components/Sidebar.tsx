'use client';
import React, { useState } from 'react';
import Link from 'next/link';
import AppLogo from '@/components/ui/AppLogo';
import Icon from '@/components/ui/AppIcon';

interface NavItem {
  label: string;
  href: string;
  icon: string;
  badge?: number;
  group?: string;
}

const clientNav: NavItem[] = [
  { label: 'Tableau de bord', href: '/', icon: 'HomeIcon', group: 'principal' },
  { label: 'Scanner QR', href: '/qr-code-scanner', icon: 'QrCodeIcon', group: 'principal' },
  { label: 'Nouveau lot', href: '/new-lot', icon: 'PlusCircleIcon', group: 'principal' },
  { label: 'Mes conteneurs', href: '/container-detail', icon: 'ArchiveBoxIcon', group: 'principal' },
  { label: 'Suivi transport', href: '/transport-tracking', icon: 'TruckIcon', group: 'transport' },
];

const adminNav: NavItem[] = [
  { label: 'Tableau de bord', href: '/admin-dashboard', icon: 'ChartBarIcon', group: 'principal' },
  { label: 'Gestion des lots', href: '/lot-management', icon: 'ClipboardDocumentListIcon', badge: 7, group: 'opérations' },
  { label: 'Conteneurs', href: '/container-detail', icon: 'ArchiveBoxIcon', group: 'opérations' },
  { label: 'Clients', href: '/', icon: 'BuildingOfficeIcon', group: 'opérations' },
  { label: 'Transports', href: '/admin-transport', icon: 'TruckIcon', group: 'opérations' },
  { label: 'Factures', href: '/', icon: 'DocumentTextIcon', badge: 3, group: 'finance' },
  { label: 'Prix métaux', href: '/', icon: 'CurrencyEuroIcon', group: 'finance' },
];

interface SidebarProps {
  activeRoute: string;
  userRole: 'client' | 'admin';
}

export default function Sidebar({ activeRoute, userRole }: SidebarProps) {
  const [collapsed, setCollapsed] = useState(false);
  const navItems = userRole === 'admin' ? adminNav : clientNav;

  const groups = Array.from(new Set(navItems.map((n) => n.group)));

  return (
    <aside
      className="hidden lg:flex flex-col bg-card border-r border-border transition-all duration-300 ease-in-out flex-shrink-0"
      style={{ width: collapsed ? 64 : 240 }}
    >
      {/* Logo */}
      <div className="flex items-center gap-3 px-4 py-4 border-b border-border min-h-[64px]">
        <AppLogo size={32} />
        {!collapsed && (
          <span className="font-bold text-base text-foreground tracking-tight truncate">
            MetalVision
          </span>
        )}
      </div>

      {/* Nav */}
      <nav className="flex-1 overflow-y-auto py-3 px-2">
        {groups.map((group) => (
          <div key={`group-${group}`} className="mb-4">
            {!collapsed && (
              <p className="text-[11px] font-600 uppercase tracking-widest text-muted-foreground px-3 mb-1">
                {group}
              </p>
            )}
            {navItems
              .filter((n) => n.group === group)
              .map((item) => {
                const isActive = activeRoute === item.href;
                return (
                  <Link
                    key={`nav-${item.href}-${item.label}`}
                    href={item.href}
                    title={collapsed ? item.label : undefined}
                    className={`flex items-center gap-3 px-3 py-2.5 rounded-lg mb-0.5 text-sm font-medium transition-all duration-150 relative ${
                      isActive ? 'sidebar-item-active' : 'sidebar-item'
                    }`}
                  >
                    <Icon
                      name={item.icon as Parameters<typeof Icon>[0]['name']}
                      size={18}
                      variant={isActive ? 'solid' : 'outline'}
                      className="flex-shrink-0"
                    />
                    {!collapsed && (
                      <>
                        <span className="truncate">{item.label}</span>
                        {item.badge !== undefined && (
                          <span className="ml-auto bg-accent text-accent-foreground text-[11px] font-700 px-1.5 py-0.5 rounded-full tabular-nums">
                            {item.badge}
                          </span>
                        )}
                      </>
                    )}
                    {collapsed && item.badge !== undefined && (
                      <span className="absolute top-1 right-1 w-2 h-2 bg-accent rounded-full" />
                    )}
                  </Link>
                );
              })}
          </div>
        ))}
      </nav>

      {/* Bottom */}
      <div className="border-t border-border p-2">
        <button
          onClick={() => setCollapsed(!collapsed)}
          className="flex items-center gap-3 w-full px-3 py-2.5 rounded-lg btn-ghost text-muted-foreground text-sm font-medium"
          aria-label={collapsed ? 'Développer le menu' : 'Réduire le menu'}
        >
          <Icon
            name={collapsed ? 'ChevronRightIcon' : 'ChevronLeftIcon'}
            size={18}
          />
          {!collapsed && <span>Réduire</span>}
        </button>

        <div className={`flex items-center gap-3 px-3 py-2.5 mt-1 rounded-lg bg-muted ${collapsed ? 'justify-center' : ''}`}>
          <div className="w-7 h-7 rounded-full bg-primary flex items-center justify-center flex-shrink-0">
            <span className="text-primary-foreground text-xs font-700">
              {userRole === 'admin' ? 'AD' : 'CL'}
            </span>
          </div>
          {!collapsed && (
            <div className="min-w-0">
              <p className="text-sm font-600 text-foreground truncate">
                {userRole === 'admin' ? 'Admin Récup.' : 'Client Industrie'}
              </p>
              <p className="text-xs text-muted-foreground truncate">
                {userRole === 'admin' ? 'Opérateur' : 'Chantier Nord'}
              </p>
            </div>
          )}
        </div>
      </div>
    </aside>
  );
}