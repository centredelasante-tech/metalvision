'use client';
import React from 'react';
import {
  AreaChart, Area, BarChart, Bar, XAxis, YAxis, CartesianGrid,
  Tooltip, ResponsiveContainer, Legend,
} from 'recharts';

const VOLUME_DATA = [
  { date: '29/05', fer: 3.2, cuivre: 0.28, aluminium: 0.5, acier: 1.1 },
  { date: '30/05', fer: 1.8, cuivre: 0.67, aluminium: 0.3, acier: 2.2 },
  { date: '31/05', fer: 2.5, cuivre: 0.31, aluminium: 1.1, acier: 0.8 },
  { date: '01/06', fer: 3.8, cuivre: 0.42, aluminium: 0.7, acier: 1.5 },
  { date: '02/06', fer: 1.2, cuivre: 0.85, aluminium: 0.9, acier: 0.6 },
  { date: '03/06', fer: 4.1, cuivre: 0.22, aluminium: 1.4, acier: 2.0 },
  { date: '04/06', fer: 2.7, cuivre: 0.68, aluminium: 0.6, acier: 1.3 },
];

const VALUE_DATA = [
  { date: '29/05', valeur: 312 },
  { date: '30/05', valeur: 487 },
  { date: '31/05', valeur: 268 },
  { date: '01/06', valeur: 543 },
  { date: '02/06', valeur: 391 },
  { date: '03/06', valeur: 628 },
  { date: '04/06', valeur: 1847 },
];

const CustomTooltip = ({ active, payload, label }: { active?: boolean; payload?: { name: string; value: number; color: string }[]; label?: string }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-card border border-border rounded-xl shadow-modal p-3 text-xs">
      <p className="font-600 text-foreground mb-2">{label}</p>
      {payload.map((p) => (
        <div key={`tooltip-${p.name}`} className="flex items-center gap-2 mb-1">
          <div className="w-2 h-2 rounded-full" style={{ backgroundColor: p.color }} />
          <span className="text-muted-foreground capitalize">{p.name}</span>
          <span className="font-600 text-foreground tabular-nums ml-auto pl-4">
            {typeof p.value === 'number' ? p.value.toFixed(2) : p.value}
          </span>
        </div>
      ))}
    </div>
  );
};

const ValueTooltip = ({ active, payload, label }: { active?: boolean; payload?: { value: number }[]; label?: string }) => {
  if (!active || !payload?.length) return null;
  return (
    <div className="bg-card border border-border rounded-xl shadow-modal p-3 text-xs">
      <p className="font-600 text-foreground mb-1">{label}</p>
      <p className="text-primary font-700 tabular-nums">{payload[0]?.value?.toFixed(0)} $CA</p>
    </div>
  );
};

export default function AdminChartsInner() {
  return (
    <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
      {/* Volume by metal type */}
      <div className="bg-card rounded-xl border border-border p-5">
        <div className="flex items-center justify-between mb-5">
          <div>
            <h3 className="text-sm font-600 text-foreground">Volume traité par métal</h3>
            <p className="text-xs text-muted-foreground mt-0.5">7 derniers jours · m³</p>
          </div>
        </div>
        <ResponsiveContainer width="100%" height={220}>
          <BarChart data={VOLUME_DATA} barSize={10} barGap={2}>
            <defs>
              <linearGradient id="grad-fer" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="var(--muted-foreground)" stopOpacity={0.9} />
                <stop offset="100%" stopColor="var(--muted-foreground)" stopOpacity={0.5} />
              </linearGradient>
            </defs>
            <CartesianGrid stroke="var(--border)" strokeDasharray="3 3" vertical={false} />
            <XAxis dataKey="date" tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} axisLine={false} tickLine={false} />
            <YAxis tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} axisLine={false} tickLine={false} width={30} />
            <Tooltip content={<CustomTooltip />} />
            <Legend wrapperStyle={{ fontSize: 11, paddingTop: 8 }} />
            <Bar dataKey="fer" name="Fer" fill="#9ca3af" radius={[3, 3, 0, 0]} />
            <Bar dataKey="cuivre" name="Cuivre" fill="var(--accent)" radius={[3, 3, 0, 0]} />
            <Bar dataKey="aluminium" name="Aluminium" fill="#93c5fd" radius={[3, 3, 0, 0]} />
            <Bar dataKey="acier" name="Acier" fill="#374151" radius={[3, 3, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </div>

      {/* Daily processed value */}
      <div className="bg-card rounded-xl border border-border p-5">
        <div className="flex items-center justify-between mb-5">
          <div>
            <h3 className="text-sm font-600 text-foreground">Valeur traitée par jour</h3>
            <p className="text-xs text-muted-foreground mt-0.5">7 derniers jours · CAD</p>
          </div>
          <div className="text-right">
            <p className="text-lg font-700 tabular-nums text-primary">4 476 $CA</p>
            <p className="text-xs text-muted-foreground">Total 7 jours</p>
          </div>
        </div>
        <ResponsiveContainer width="100%" height={220}>
          <AreaChart data={VALUE_DATA}>
            <defs>
              <linearGradient id="grad-value" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="var(--primary)" stopOpacity={0.25} />
                <stop offset="100%" stopColor="var(--primary)" stopOpacity={0.02} />
              </linearGradient>
            </defs>
            <CartesianGrid stroke="var(--border)" strokeDasharray="3 3" vertical={false} />
            <XAxis dataKey="date" tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} axisLine={false} tickLine={false} />
            <YAxis tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }} axisLine={false} tickLine={false} width={40} />
            <Tooltip content={<ValueTooltip />} />
            <Area
              type="monotone"
              dataKey="valeur"
              stroke="var(--primary)"
              strokeWidth={2}
              fill="url(#grad-value)"
              dot={false}
              activeDot={{ r: 5, fill: 'var(--primary)' }}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>
    </div>
  );
}