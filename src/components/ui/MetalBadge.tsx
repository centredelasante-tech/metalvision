import React from 'react';

type MetalType = 'fer' | 'acier' | 'aluminium' | 'cuivre' | 'laiton' | 'inox';

const METAL_CONFIG: Record<MetalType, { label: string; className: string }> = {
  fer: { label: 'Fer', className: 'metal-badge-fer' },
  acier: { label: 'Acier', className: 'metal-badge-acier' },
  aluminium: { label: 'Aluminium', className: 'metal-badge-aluminium' },
  cuivre: { label: 'Cuivre', className: 'metal-badge-cuivre' },
  laiton: { label: 'Laiton', className: 'metal-badge-laiton' },
  inox: { label: 'Inox', className: 'metal-badge-inox' },
};

interface MetalBadgeProps {
  metal: MetalType | string;
}

export default function MetalBadge({ metal }: MetalBadgeProps) {
  const key = metal.toLowerCase() as MetalType;
  const config = METAL_CONFIG[key] ?? { label: metal, className: 'metal-badge-fer' };
  return (
    <span className={`inline-flex items-center rounded-md text-xs font-600 px-2 py-0.5 ${config.className}`}>
      {config.label}
    </span>
  );
}