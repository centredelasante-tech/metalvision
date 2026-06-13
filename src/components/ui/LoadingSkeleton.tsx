import React from 'react';

interface SkeletonProps {
  className?: string;
}

export function Skeleton({ className = '' }: SkeletonProps) {
  return (
    <div className={`animate-pulse bg-muted rounded-md ${className}`} />
  );
}

export function MetricCardSkeleton() {
  return (
    <div className="rounded-xl border border-border bg-card p-5">
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <Skeleton className="h-3 w-24 mb-3" />
          <Skeleton className="h-8 w-20" />
          <Skeleton className="h-3 w-16 mt-2" />
        </div>
        <Skeleton className="w-10 h-10 rounded-lg" />
      </div>
    </div>
  );
}

export function TableRowSkeleton({ cols }: { cols: number }) {
  return (
    <tr>
      {Array.from({ length: cols }).map((_, i) => (
        <td key={`skel-col-${i + 1}`} className="px-4 py-3">
          <Skeleton className="h-4 w-full" />
        </td>
      ))}
    </tr>
  );
}