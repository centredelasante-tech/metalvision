import React from 'react';
import ContainerHeader from './ContainerHeader';
import ContainerInfoPanel from './ContainerInfoPanel';
import ContainerQRCode from './ContainerQRCode';
import SensorPanel from './SensorPanel';
import ContainerFillChart from './ContainerFillChart';
import ContainerLotHistory from './ContainerLotHistory';

export default function ContainerDetailContent() {
  return (
    <div className="space-y-4 md:space-y-6">
      <ContainerHeader />

      <div className="flex flex-col xl:grid xl:grid-cols-3 gap-4 md:gap-6">
        {/* Left column */}
        <div className="space-y-4 md:space-y-5">
          <ContainerInfoPanel />
          {/* QR code max 200x200 on mobile */}
          <div className="max-w-[200px] mx-auto xl:max-w-none">
            <ContainerQRCode />
          </div>
          <SensorPanel />
        </div>

        {/* Right columns */}
        <div className="xl:col-span-2 space-y-4 md:space-y-5">
          <ContainerFillChart />
          <ContainerLotHistory />
        </div>
      </div>
    </div>
  );
}