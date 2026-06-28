import React from 'react';
import Sidebar from './Sidebar';
import Topbar from './Topbar';
import MobileBottomNav from './MobileBottomNav';

interface AppLayoutProps {
  children: React.ReactNode;
  activeRoute?: string;
  userRole?: 'client' | 'admin' | 'verifier';
}

export default function AppLayout({
  children,
  activeRoute = '/',
  userRole = 'client',
}: AppLayoutProps) {
  return (
    <div className="flex h-screen overflow-hidden bg-background">
      <Sidebar activeRoute={activeRoute} userRole={userRole} />
      <div className="flex flex-col flex-1 min-w-0 overflow-hidden">
        <Topbar userRole={userRole as 'client' | 'admin'} />
        <main className="flex-1 overflow-y-auto pb-20 lg:pb-0">
          <div className="max-w-screen-2xl mx-auto px-4 md:px-6 lg:px-8 xl:px-10 2xl:px-12 py-4 md:py-6">
            {children}
          </div>
        </main>
      </div>
      {/* Mobile bottom navigation */}
      <MobileBottomNav activeRoute={activeRoute} userRole={userRole} />
    </div>
  );
}