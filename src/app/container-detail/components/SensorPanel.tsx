import React from 'react';
import Icon from '@/components/ui/AppIcon';

const SENSOR = {
  id: 'sen-042',
  type: 'Ultrason',
  fillLevel: 92,
  battery: 18,
  lastUpdate: '04/06/2026 13:58',
  temperature: '24°C',
  status: 'critical' as const,
};

export default function SensorPanel() {
  const batteryColor =
    SENSOR.battery <= 20 ? 'text-red-600' :
    SENSOR.battery <= 40 ? 'text-amber-600' : 'text-primary';

  const fillColor =
    SENSOR.fillLevel >= 85 ? 'bg-red-500' :
    SENSOR.fillLevel >= 65 ? 'bg-accent' : 'bg-primary';

  return (
    <div className={`bg-card rounded-xl border overflow-hidden ${
      SENSOR.status === 'critical' ? 'border-red-200' : 'border-border'
    }`}>
      <div className={`flex items-center justify-between px-5 py-4 border-b ${
        SENSOR.status === 'critical' ? 'bg-red-50 border-red-200' : 'border-border'
      }`}>
        <div className="flex items-center gap-2">
          <Icon name="SignalIcon" size={16} className={SENSOR.status === 'critical' ? 'text-red-600' : 'text-primary'} />
          <h3 className="text-sm font-600 text-foreground">Capteur {SENSOR.type}</h3>
        </div>
        <span className={`text-xs font-600 px-2 py-0.5 rounded-full ${
          SENSOR.status === 'critical' ? 'bg-red-100 text-red-600' : 'bg-secondary text-primary'
        }`}>
          {SENSOR.status === 'critical' ? 'Alerte' : 'OK'}
        </span>
      </div>

      <div className="p-5 space-y-4">
        {/* Fill level */}
        <div>
          <div className="flex justify-between items-center mb-2">
            <span className="text-xs font-600 text-muted-foreground">Niveau de remplissage</span>
            <span className={`text-sm font-700 tabular-nums ${SENSOR.fillLevel >= 85 ? 'text-red-600' : 'text-foreground'}`}>
              {SENSOR.fillLevel}%
            </span>
          </div>
          <div className="h-3 bg-muted rounded-full overflow-hidden">
            <div
              className={`h-full rounded-full transition-all ${fillColor}`}
              style={{ width: `${SENSOR.fillLevel}%` }}
            />
          </div>
          {SENSOR.fillLevel >= 85 && (
            <p className="text-xs text-red-600 mt-1.5 flex items-center gap-1">
              <Icon name="ExclamationTriangleIcon" size={12} />
              Collecte urgente requise
            </p>
          )}
        </div>

        {/* Stats grid */}
        <div className="grid grid-cols-3 gap-2">
          <div className="text-center p-2.5 bg-muted rounded-lg">
            <Icon name="BoltIcon" size={16} className={`${batteryColor} mx-auto mb-1`} />
            <p className={`text-sm font-700 tabular-nums ${batteryColor}`}>{SENSOR.battery}%</p>
            <p className="text-[10px] text-muted-foreground">Batterie</p>
          </div>
          <div className="text-center p-2.5 bg-muted rounded-lg">
            <Icon name="SunIcon" size={16} className="text-muted-foreground mx-auto mb-1" />
            <p className="text-sm font-700 text-foreground">{SENSOR.temperature}</p>
            <p className="text-[10px] text-muted-foreground">Temp.</p>
          </div>
          <div className="text-center p-2.5 bg-muted rounded-lg">
            <Icon name="WifiIcon" size={16} className="text-primary mx-auto mb-1" />
            <p className="text-sm font-700 text-primary">LoRa</p>
            <p className="text-[10px] text-muted-foreground">Réseau</p>
          </div>
        </div>

        <p className="text-[11px] text-muted-foreground flex items-center gap-1.5">
          <Icon name="ClockIcon" size={12} />
          Dernière lecture : {SENSOR.lastUpdate}
        </p>

        <div className="flex gap-2">
          <button className="flex-1 py-2 rounded-lg text-xs font-600 border border-border btn-ghost flex items-center justify-center gap-1.5">
            <Icon name="ArrowPathIcon" size={13} />
            Rafraîchir
          </button>
          <button className="flex-1 py-2 rounded-lg text-xs font-600 border border-border btn-ghost flex items-center justify-center gap-1.5">
            <Icon name="Cog6ToothIcon" size={13} />
            Configurer
          </button>
        </div>
      </div>
    </div>
  );
}