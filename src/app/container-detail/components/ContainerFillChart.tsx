'use client';
import React from 'react';
import dynamic from 'next/dynamic';

const ContainerFillChartInner = dynamic(() => import('./ContainerFillChartInner'), { ssr: false });

export default function ContainerFillChart() {
  return <ContainerFillChartInner />;
}