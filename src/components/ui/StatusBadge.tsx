import React from 'react';

type LotStatus = 'submitted' | 'processed' | 'invoiced';
type InvoiceStatus = 'draft' | 'sent' | 'paid';

type StatusType = LotStatus | InvoiceStatus;

const STATUS_CONFIG: Record<StatusType, { label: string; className: string }> = {
  submitted: { label: 'Soumis', className: 'status-submitted' },
  processed: { label: 'Traité', className: 'status-processed' },
  invoiced: { label: 'Facturé', className: 'status-invoiced' },
  draft: { label: 'Brouillon', className: 'status-draft' },
  sent: { label: 'Envoyée', className: 'status-sent' },
  paid: { label: 'Payée', className: 'status-paid' },
};

interface StatusBadgeProps {
  status: StatusType;
  size?: 'sm' | 'md';
}

export default function StatusBadge({ status, size = 'md' }: StatusBadgeProps) {
  const config = STATUS_CONFIG[status] ?? { label: status, className: 'status-submitted' };
  return (
    <span
      className={`inline-flex items-center rounded-full font-600 ${config.className} ${
        size === 'sm' ? 'text-[11px] px-2 py-0.5' : 'text-xs px-2.5 py-1'
      }`}
    >
      {config.label}
    </span>
  );
}