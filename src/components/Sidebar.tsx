'use client';
import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import AppLogo from '@/components/ui/AppLogo';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';

interface NavItem {
  label: string;
  href: string;
  icon: string;
  badgeKey?: 'lots' | 'factures';
  group?: string;
}

const clientNav: NavItem[] = [
  { label: 'Tableau de bord', href: '/', icon: 'HomeIcon', group: 'principal' },
  { label: 'Scanner QR', href: '/qr-code-scanner', icon: 'QrCodeIcon', group: 'principal' },
  { label: 'Nouveau lot', href: '/new-lot', icon: 'PlusCircleIcon', group: 'principal' },
  { label: 'Mes conteneurs', href: '/lot-management', icon: 'ArchiveBoxIcon', group: 'principal' },
  { label: 'Suivi transport', href: '/transport-tracking', icon: 'TruckIcon', group: 'transport' },
  { label: 'Impact Carbone', href: '/carbon-impact', icon: 'CloudIcon', group: 'carbone' },
  { label: 'Capacités', href: '/capacites', icon: 'CubeIcon', group: 'réseau' },
  { label: 'Opportunités', href: '/opportunities', icon: 'LightBulbIcon', group: 'réseau' },
  { label: 'Mandats', href: '/mandats', icon: 'DocumentCheckIcon', group: 'réseau' },
  { label: 'Projets', href: '/projets', icon: 'FolderIcon', group: 'réseau' },
  { label: 'Documents', href: '/documents', icon: 'FolderOpenIcon', group: 'réseau' },
  { label: 'Événements', href: '/evenements', icon: 'BoltIcon', group: 'réseau' },
  { label: 'Cockpit', href: '/cockpit', icon: 'PresentationChartLineIcon', group: 'réseau' },
];

const adminNav: NavItem[] = [
  { label: 'Tableau de bord', href: '/admin-dashboard', icon: 'ChartBarIcon', group: 'principal' },
  { label: 'Gestion des lots', href: '/lot-management', icon: 'ClipboardDocumentListIcon', badgeKey: 'lots', group: 'opérations' },
  { label: 'Conteneurs', href: '/lot-management', icon: 'ArchiveBoxIcon', group: 'opérations' },
  { label: 'Clients', href: '/', icon: 'BuildingOfficeIcon', group: 'opérations' },
  { label: 'Organisations', href: '/organizations', icon: 'BuildingOffice2Icon', group: 'opérations' },
  { label: 'Transports', href: '/admin-transport', icon: 'TruckIcon', group: 'opérations' },
  { label: 'Capacités', href: '/capacites', icon: 'CubeIcon', group: 'réseau' },
  { label: 'Opportunités', href: '/opportunities', icon: 'LightBulbIcon', group: 'réseau' },
  { label: 'Mandats', href: '/mandats', icon: 'DocumentCheckIcon', group: 'réseau' },
  { label: 'Projets', href: '/projets', icon: 'FolderIcon', group: 'réseau' },
  { label: 'Documents', href: '/documents', icon: 'FolderOpenIcon', group: 'réseau' },
  { label: 'Événements', href: '/evenements', icon: 'BoltIcon', group: 'réseau' },
  { label: 'Cockpit', href: '/cockpit', icon: 'PresentationChartLineIcon', group: 'réseau' },
  { label: 'Factures', href: '/', icon: 'DocumentTextIcon', badgeKey: 'factures', group: 'finance' },
  { label: 'Prix métaux', href: '/', icon: 'CurrencyEuroIcon', group: 'finance' },
  { label: 'Projets Carbone', href: '/admin-carbon-projects', icon: 'FolderIcon', group: 'mrv' },
  { label: 'Facteurs GES', href: '/admin-emission-factors', icon: 'BeakerIcon', group: 'mrv' },
  { label: 'Vérifications', href: '/admin-verification-sessions', icon: 'CheckBadgeIcon', group: 'mrv' },
];

const verifierNav: NavItem[] = [
  { label: 'Vue MRV', href: '/verifier-mrv', icon: 'ClipboardDocumentListIcon', group: 'vérification' },
];

interface SidebarProps {
  activeRoute: string;
  userRole: 'client' | 'admin' | 'verifier';
}

const ROLE_LABELS: Record<string, string> = {
  admin: 'Administrateur',
  membre: 'Membre',
};

export default function Sidebar({ activeRoute, userRole }: SidebarProps) {
  const [collapsed, setCollapsed] = useState(false);
  const [companyName, setCompanyName] = useState<string | null>(null);
  const [memberRole, setMemberRole] = useState<string | null>(null);
  const [submittedLotsCount, setSubmittedLotsCount] = useState<number>(0);

  const navItems = userRole === 'admin' ? adminNav : userRole === 'verifier' ? verifierNav : clientNav;
  const groups = Array.from(new Set(navItems.map((n) => n.group)));

  useEffect(() => {
    if (userRole !== 'client') return;
    const supabase = createClient();
    supabase.auth.getUser().then(({ data: { user } }) => {
      if (!user) return;
      supabase
        .from('organization_members')
        .select('org_role, organizations(name)')
        .eq('user_id', user.id)
        .limit(1)
        .single()
        .then(({ data }) => {
          if (!data) return;
          setMemberRole((data.org_role as string) ?? null);
          const name = (data.organizations as { name: string } | null)?.name ?? null;
          setCompanyName(name);
        });
    });
  }, [userRole]);

  useEffect(() => {
    if (userRole !== 'admin') return;
    const supabase = createClient();
    supabase
      .from('raw_measurements')
      .select('id', { count: 'exact', head: true })
      .eq('status', 'submitted')
      .then(({ count }) => {
        setSubmittedLotsCount(count ?? 0);
      });
  }, [userRole]);

  const getBadgeValue = (badgeKey?: 'lots' | 'factures'): number | undefined => {
    if (!badgeKey) return undefined;
    if (badgeKey === 'lots') return submittedLotsCount;
    if (badgeKey === 'factures') return 0;
    return undefined;
  };

  // Resolve display values
  const displayName =
    userRole === 'admin' ?'Admin Récup.'
      : userRole === 'verifier' ?'Vérificateur' : companyName ??'Chargement…';

  const displaySubtitle =
    userRole === 'admin' ?'Opérateur'
      : userRole === 'verifier' ?'ISO 14064-2'
      : memberRole
      ? (ROLE_LABELS[memberRole] ?? memberRole)
      : '…';

  const avatarInitials =
    userRole === 'admin' ? 'AD' : userRole === 'verifier' ? 'VR' : 'CL';

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
            METALTRACE
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
                const badgeValue = getBadgeValue(item.badgeKey);
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
                        {badgeValue !== undefined && badgeValue > 0 && (
                          <span className="ml-auto bg-accent text-accent-foreground text-[11px] font-700 px-1.5 py-0.5 rounded-full tabular-nums">
                            {badgeValue}
                          </span>
                        )}
                      </>
                    )}
                    {collapsed && badgeValue !== undefined && badgeValue > 0 && (
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
              {avatarInitials}
            </span>
          </div>
          {!collapsed && (
            <div className="min-w-0">
              <p className="text-sm font-600 text-foreground truncate">
                {displayName}
              </p>
              <p className="text-xs text-muted-foreground truncate">
                {displaySubtitle}
              </p>
            </div>
          )}
        </div>
      </div>
    </aside>
  );
}