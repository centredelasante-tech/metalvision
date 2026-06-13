import React from 'react';
import Icon from '@/components/ui/AppIcon';

interface EmptyStateProps {
  icon: string;
  title: string;
  description: string;
  action?: {
    label: string;
    onClick: () => void;
  };
}

export default function EmptyState({ icon, title, description, action }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center py-16 px-6 text-center">
      <div className="w-16 h-16 rounded-2xl bg-muted flex items-center justify-center mb-4">
        <Icon name={icon as Parameters<typeof Icon>[0]['name']} size={32} className="text-muted-foreground" />
      </div>
      <h3 className="text-base font-600 text-foreground mb-2">{title}</h3>
      <p className="text-sm text-muted-foreground max-w-xs">{description}</p>
      {action && (
        <button
          onClick={action.onClick}
          className="mt-5 btn-primary px-4 py-2 rounded-lg text-sm font-600"
        >
          {action.label}
        </button>
      )}
    </div>
  );
}