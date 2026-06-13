import React from 'react';
import Sidebar from './Sidebar';
import Topbar from './Topbar';

interface AppLayoutProps {
  children: React.ReactNode;
  activeRoute?: string;
  userRole?: 'client' | 'admin';
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
        <Topbar userRole={userRole} />
        <main className="flex-1 overflow-y-auto">
          <div className="max-w-screen-2xl mx-auto px-6 lg:px-8 xl:px-10 2xl:px-12 py-6">
            {children}
          </div>
        </main>
      </div>
    </div>
  );
}