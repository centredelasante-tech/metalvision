'use client';
import React, { useEffect, useState, useCallback } from 'react';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';
import StatusBadge from '@/components/ui/StatusBadge';
import MetricCard from '@/components/ui/MetricCard';
import { TableRowSkeleton, MetricCardSkeleton } from '@/components/ui/LoadingSkeleton';

// ─── Types ────────────────────────────────────────────────────────────────────

interface Organization {
  id: string;
  name: string;
  type: string | null;
  region: string | null;
  status: 'draft' | 'active' | 'suspended' | 'archived';
  member_count: number;
}

type OrgStatus = 'draft' | 'active' | 'suspended' | 'archived';

const STATUS_LABELS: Record<OrgStatus, string> = {
  draft: 'Brouillon',
  active: 'Actif',
  suspended: 'Suspendu',
  archived: 'Archivé',
};

// ─── Page ─────────────────────────────────────────────────────────────────────

export default function OrganizationsPage() {
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<OrgStatus | ''>('');
  const [isPlatformAdmin, setIsPlatformAdmin] = useState(false);

  // Detect platform admin from JWT app_metadata
  useEffect(() => {
    const supabase = createClient();
    supabase.auth.getSession().then(({ data: { session } }) => {
      const role = session?.user?.app_metadata?.role;
      setIsPlatformAdmin(role === 'admin' || role === 'project_admin');
    });
  }, []);

  const fetchOrganizations = useCallback(async () => {
    setLoading(true);
    setError(null);
    const supabase = createClient();

    // Query: organizations + member count via organization_members
    const { data, error: fetchError } = await supabase
      .from('organizations')
      .select(`
        id,
        name,
        type,
        region,
        status,
        organization_members(id)
      `)
      .order('name', { ascending: true });

    if (fetchError) {
      setError(fetchError.message);
      setLoading(false);
      return;
    }

    const mapped: Organization[] = (data ?? []).map((row: any) => ({
      id: row.id,
      name: row.name,
      type: row.type ?? null,
      region: row.region ?? null,
      status: row.status as OrgStatus,
      member_count: Array.isArray(row.organization_members) ? row.organization_members.length : 0,
    }));

    setOrganizations(mapped);
    setLoading(false);
  }, []);

  useEffect(() => { fetchOrganizations(); }, [fetchOrganizations]);

  // Client-side filtering
  const filtered = organizations.filter((org) => {
    const matchSearch =
      search.trim() === '' ||
      org.name.toLowerCase().includes(search.toLowerCase());
    const matchStatus = statusFilter === '' || org.status === statusFilter;
    return matchSearch && matchStatus;
  });

  // Metrics
  const totalActive = organizations.filter((o) => o.status === 'active').length;
  const totalMembers = organizations.reduce((s, o) => s + o.member_count, 0);

  return (
    <AppLayout>
      <div className="min-h-screen bg-background">
        <div className="max-w-6xl mx-auto px-4 py-8">

          {/* Header */}
          <div className="flex items-start justify-between mb-6 gap-4">
            <div>
              <h1 className="text-2xl font-700 text-foreground">Organisations</h1>
              <p className="text-sm text-muted-foreground mt-1">
                Gérez les organisations et leurs membres
              </p>
            </div>
            {isPlatformAdmin && (
              <Link
                href="/organizations/new"
                className="btn-primary flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600"
              >
                <Icon name="PlusIcon" size={16} />
                Nouvelle organisation
              </Link>
            )}
          </div>

          {/* Metrics */}
          <div className="grid grid-cols-2 lg:grid-cols-3 gap-4 mb-6">
            {loading ? (
              <>
                <MetricCardSkeleton />
                <MetricCardSkeleton />
                <MetricCardSkeleton />
              </>
            ) : (
              <>
                <MetricCard
                  label="Total organisations"
                  value={String(organizations.length)}
                  icon="BuildingOffice2Icon"
                  variant="default"
                />
                <MetricCard
                  label="Actives"
                  value={String(totalActive)}
                  icon="CheckCircleIcon"
                  variant="positive"
                />
                <MetricCard
                  label="Membres total"
                  value={String(totalMembers)}
                  icon="UsersIcon"
                  variant="default"
                />
              </>
            )}
          </div>

          {/* Filters */}
          <div className="flex flex-col sm:flex-row gap-3 mb-5">
            <div className="relative flex-1">
              <Icon
                name="MagnifyingGlassIcon"
                size={16}
                className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground"
              />
              <input
                type="text"
                className="input w-full pl-9 text-sm"
                placeholder="Rechercher par nom…"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </div>
            <select
              className="input text-sm py-2 pr-8 min-w-[160px]"
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value as OrgStatus | '')}
            >
              <option value="">Tous les statuts</option>
              {(Object.keys(STATUS_LABELS) as OrgStatus[]).map((s) => (
                <option key={s} value={s}>{STATUS_LABELS[s]}</option>
              ))}
            </select>
          </div>

          {/* Error */}
          {error && (
            <div className="rounded-lg bg-red-50 border border-red-200 px-4 py-3 mb-5 flex items-start gap-2">
              <Icon name="ExclamationTriangleIcon" size={16} className="text-red-500 mt-0.5 flex-shrink-0" />
              <p className="text-sm text-red-700">{error}</p>
            </div>
          )}

          {/* Table */}
          <div className="bg-card rounded-xl border border-border overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-border bg-muted/40">
                    <th className="text-left px-4 py-3 font-600 text-muted-foreground text-xs uppercase tracking-wide">
                      Nom
                    </th>
                    <th className="text-left px-4 py-3 font-600 text-muted-foreground text-xs uppercase tracking-wide hidden sm:table-cell">
                      Type
                    </th>
                    <th className="text-left px-4 py-3 font-600 text-muted-foreground text-xs uppercase tracking-wide hidden md:table-cell">
                      Région
                    </th>
                    <th className="text-left px-4 py-3 font-600 text-muted-foreground text-xs uppercase tracking-wide">
                      Statut
                    </th>
                    <th className="text-right px-4 py-3 font-600 text-muted-foreground text-xs uppercase tracking-wide hidden sm:table-cell">
                      Membres
                    </th>
                    <th className="w-10" />
                  </tr>
                </thead>
                <tbody className="divide-y divide-border">
                  {loading ? (
                    Array.from({ length: 5 }).map((_, i) => (
                      <TableRowSkeleton key={`skel-${i + 1}`} cols={6} />
                    ))
                  ) : filtered.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="px-4 py-12 text-center text-muted-foreground text-sm">
                        {organizations.length === 0
                          ? 'Aucune organisation trouvée.' :'Aucun résultat pour ces critères.'}
                      </td>
                    </tr>
                  ) : (
                    filtered.map((org) => (
                      <tr
                        key={org.id}
                        className="hover:bg-muted/30 transition-colors"
                      >
                        <td className="px-4 py-3">
                          <Link
                            href={`/organizations/${org.id}`}
                            className="font-600 text-foreground hover:text-primary transition-colors"
                          >
                            {org.name}
                          </Link>
                        </td>
                        <td className="px-4 py-3 text-muted-foreground hidden sm:table-cell">
                          {org.type ?? <span className="text-muted-foreground/50">—</span>}
                        </td>
                        <td className="px-4 py-3 text-muted-foreground hidden md:table-cell">
                          {org.region ?? <span className="text-muted-foreground/50">—</span>}
                        </td>
                        <td className="px-4 py-3">
                          <OrgStatusBadge status={org.status} />
                        </td>
                        <td className="px-4 py-3 text-right tabular-nums text-muted-foreground hidden sm:table-cell">
                          {org.member_count}
                        </td>
                        <td className="px-4 py-3 text-right">
                          <Link
                            href={`/organizations/${org.id}`}
                            className="btn-ghost p-1.5 rounded-lg inline-flex"
                            title="Voir la fiche"
                          >
                            <Icon name="ChevronRightIcon" size={16} className="text-muted-foreground" />
                          </Link>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
            {!loading && filtered.length > 0 && (
              <div className="px-4 py-2.5 border-t border-border bg-muted/20 text-xs text-muted-foreground">
                {filtered.length} organisation{filtered.length > 1 ? 's' : ''}
                {statusFilter || search ? ` sur ${organizations.length}` : ''}
              </div>
            )}
          </div>

        </div>
      </div>
    </AppLayout>
  );
}

// ─── Inline org status badge (extends StatusBadge concept) ────────────────────

function OrgStatusBadge({ status }: { status: OrgStatus }) {
  const CONFIG: Record<OrgStatus, { label: string; cls: string }> = {
    draft:     { label: 'Brouillon', cls: 'text-gray-600 bg-gray-100 border-gray-200' },
    active:    { label: 'Actif',     cls: 'text-green-700 bg-green-50 border-green-200' },
    suspended: { label: 'Suspendu',  cls: 'text-amber-700 bg-amber-50 border-amber-200' },
    archived:  { label: 'Archivé',   cls: 'text-slate-500 bg-slate-100 border-slate-200' },
  };
  const cfg = CONFIG[status] ?? CONFIG.draft;
  return (
    <span className={`inline-flex items-center rounded-full text-xs font-600 px-2.5 py-1 border ${cfg.cls}`}>
      {cfg.label}
    </span>
  );
}
