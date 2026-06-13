'use client';
import React from 'react';
import {
  LineChart, Line, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, ReferenceLine,
} from 'recharts';

const FILL_HISTORY = [
  { date: '20/05', level: 12 },
  { date: '22/05', level: 28 },
  { date: '24/05', level: 41 },
  { date: '26/05', level: 55 },
  { date: '28/05', level: 48 },
  { date: '30/05', level: 63 },
  { date: '01/06', level: 71 },
  { date: '02/06', level: 78 },
  { date: '03/06', level: 85 },
  { date: '04/06', level: 92 },
];

const FillTooltip = ({ active, payload, label }: { active?: boolean; payload?: { value: number }[]; label?: string }) => {
  if (!active || !payload?.length) return null;
  const val = payload[0]?.value ?? 0;
  return (
    <div className="bg-card border border-border rounded-xl shadow-modal p-3 text-xs">
      <p className="font-600 text-foreground mb-1">{label}</p>
      <p className={`font-700 tabular-nums ${val >= 85 ? 'text-red-600' : val >= 65 ? 'text-amber-600' : 'text-primary'}`}>
        {val}% rempli
      </p>
    </div>
  );
};

export default function ContainerFillChartInner() {
  return (
    <div className="bg-card rounded-xl border border-border p-5">
      <div className="flex items-center justify-between mb-5">
        <div>
          <h3 className="text-sm font-600 text-foreground">Évolution du niveau de remplissage</h3>
          <p className="text-xs text-muted-foreground mt-0.5">CT-003 · 15 derniers jours · données capteur ultrason</p>
        </div>
        <div className="flex items-center gap-2">
          <div className="flex items-center gap-1.5">
            <div className="w-2.5 h-2.5 rounded-full bg-red-500" />
            <span className="text-xs text-muted-foreground">Seuil critique (85%)</span>
          </div>
        </div>
      </div>
      <ResponsiveContainer width="100%" height={200}>
        <LineChart data={FILL_HISTORY}>
          <CartesianGrid stroke="var(--border)" strokeDasharray="3 3" vertical={false} />
          <XAxis dataKey="date" tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} axisLine={false} tickLine={false} />
          <YAxis
            tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }}
            axisLine={false}
            tickLine={false}
            domain={[0, 100]}
            tickFormatter={(v) => `${v}%`}
            width={38}
          />
          <Tooltip content={<FillTooltip />} />
          <ReferenceLine y={85} stroke="#ef4444" strokeDasharray="4 4" strokeWidth={1.5} />
          <Line
            type="monotone"
            dataKey="level"
            stroke="var(--primary)"
            strokeWidth={2.5}
            dot={false}
            activeDot={{ r: 6, fill: 'var(--primary)' }}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}