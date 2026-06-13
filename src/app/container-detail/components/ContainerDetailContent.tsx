import React from 'react';
import ContainerHeader from './ContainerHeader';
import ContainerInfoPanel from './ContainerInfoPanel';
import ContainerQRCode from './ContainerQRCode';
import SensorPanel from './SensorPanel';
import ContainerFillChart from './ContainerFillChart';
import ContainerLotHistory from './ContainerLotHistory';

export default function ContainerDetailContent() {
  return (
    <div className="space-y-6">
      <ContainerHeader />

      <div className="grid grid-cols-1 xl:grid-cols-3 gap-6">
        {/* Left column */}
        <div className="space-y-5">
          <ContainerInfoPanel />
          <ContainerQRCode />
          <SensorPanel />
        </div>

        {/* Right columns */}
        <div className="xl:col-span-2 space-y-5">
          <ContainerFillChart />
          <ContainerLotHistory />
        </div>
      </div>
    </div>
  );
}