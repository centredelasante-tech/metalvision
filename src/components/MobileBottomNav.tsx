'use client';
import React from 'react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import Icon from '@/components/ui/AppIcon';

interface MobileBottomNavProps {
  activeRoute: string;
  userRole: 'client' | 'admin' | 'verifier';
}

const clientItems = [
  { label: 'Accueil', href: '/', icon: 'HomeIcon' },
  { label: 'Scanner', href: '/qr-code-scanner', icon: 'QrCodeIcon' },
  { label: 'Nouveau lot', href: '/new-lot', icon: 'PlusCircleIcon' },
  { label: 'Transport', href: '/transport-tracking', icon: 'TruckIcon' },
  { label: 'Carbone', href: '/carbon-impact', icon: 'CloudIcon' },
];

const adminItems = [
  { label: 'Dashboard', href: '/admin-dashboard', icon: 'ChartBarIcon' },
  { label: 'Lots', href: '/lot-management', icon: 'ClipboardDocumentListIcon' },
  { label: 'Scanner', href: '/qr-code-scanner', icon: 'QrCodeIcon' },
  { label: 'Transport', href: '/admin-transport', icon: 'TruckIcon' },
  { label: 'Carbone', href: '/admin-carbon-projects', icon: 'FolderIcon' },
];

const verifierItems = [
  { label: 'MRV', href: '/verifier-mrv', icon: 'ClipboardDocumentListIcon' },
];

export default function MobileBottomNav({ activeRoute, userRole }: MobileBottomNavProps) {
  const pathname = usePathname();
  const currentPath = pathname || activeRoute;

  const items =
    userRole === 'admin' ? adminItems :
    userRole === 'verifier' ? verifierItems :
    clientItems;

  return (
    <nav className="lg:hidden fixed bottom-0 left-0 right-0 z-50 bg-card border-t border-border safe-area-bottom">
      <div className="flex items-center justify-around px-2 py-1">
        {items.map((item) => {
          const isActive = currentPath === item.href;
          return (
            <Link
              key={`bottom-nav-${item.href}`}
              href={item.href}
              className={`flex flex-col items-center gap-0.5 px-3 py-2 rounded-xl min-w-[56px] transition-all ${
                isActive
                  ? 'text-primary' :'text-muted-foreground'
              }`}
            >
              <Icon
                name={item.icon as Parameters<typeof Icon>[0]['name']}
                size={22}
                variant={isActive ? 'solid' : 'outline'}
              />
              <span className={`text-[10px] font-600 ${isActive ? 'text-primary' : 'text-muted-foreground'}`}>
                {item.label}
              </span>
              {isActive && (
                <span className="absolute bottom-0 w-1 h-1 bg-primary rounded-full" />
              )}
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
