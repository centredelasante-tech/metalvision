'use client';
import React from 'react';
import dynamic from 'next/dynamic';

const AdminChartsInner = dynamic(() => import('./AdminChartsInner'), { ssr: false });

export default function AdminCharts() {
  return <AdminChartsInner />;
}