'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Sidebar from './Sidebar';
import Topbar from './Topbar';
import MobileBottomNav from './MobileBottomNav';
import { createClient } from '@/lib/supabase/client';

interface AppLayoutProps {
  children: React.ReactNode;
  activeRoute?: string;
  userRole?: 'client' | 'admin' | 'verifier';
}

export default function AppLayout({
  children,
  activeRoute = '/',
  userRole: userRoleProp,
}: AppLayoutProps) {
  const router = useRouter();
  const [userRole, setUserRole] = useState<'client' | 'admin' | 'verifier'>(
    userRoleProp ?? 'client'
  );
  const [checkingAccess, setCheckingAccess] = useState(true);

  useEffect(() => {
    const fetchRole = async () => {
      const supabase = createClient();
      const { data: { user } } = await supabase.auth.getUser();
      const role = user?.app_metadata?.role ?? user?.user_metadata?.role ?? 'client';
      const normalised: 'client' | 'admin' | 'verifier' =
        role === 'verifier' ? 'verifier' : role === 'admin' || role === 'project_admin' ? 'admin' : 'client';
      setUserRole(normalised);

      const roleRoutes: Record<'client' | 'admin' | 'verifier', string> = {
        verifier: '/verifier-mrv',
        admin: '/admin-dashboard',
        client: '/',
      };

      if (userRoleProp && normalised !== userRoleProp) {
        router.replace(roleRoutes[normalised]);
        return;
      }
      setCheckingAccess(false);
    };
    fetchRole();
  }, []);

  if (checkingAccess) {
    return (
      <div className="flex h-screen items-center justify-center bg-background">
        <div className="w-8 h-8 border-4 border-primary border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

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