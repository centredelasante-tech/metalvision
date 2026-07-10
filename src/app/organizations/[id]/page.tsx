'use client';
import React, { useEffect, useState, useCallback } from 'react';
import Link from 'next/link';
import { useParams } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';

// ─── Types ────────────────────────────────────────────────────────────────────

interface Organization {
  id: string;
  name: string;
  type: string | null;
  neq: string | null;
  address: string | null;
  region: string | null;
  maturity_level: string | null;
  primary_contact_email: string | null;
  status: 'draft' | 'active' | 'suspended' | 'archived';
}

interface OrgMember {
  id: string;
  user_id: string;
  org_role: 'admin' | 'membre';
  operational_profile: 'bureau' | 'terrain';
  status: 'invited' | 'active' | 'suspended' | 'revoked';
  invited_at: string | null;
  activated_at: string | null;
  profiles?: { full_name: string | null; email: string | null } | null;
}

type OrgStatus = 'draft' | 'active' | 'suspended' | 'archived';
type MemberStatus = 'invited' | 'active' | 'suspended' | 'revoked';

// ─── Status badge configs ─────────────────────────────────────────────────────

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

function MemberStatusBadge({ status }: { status: MemberStatus }) {
  const CONFIG: Record<MemberStatus, { label: string; cls: string }> = {
    invited:   { label: 'Invité',    cls: 'text-blue-700 bg-blue-50 border-blue-200' },
    active:    { label: 'Actif',     cls: 'text-green-700 bg-green-50 border-green-200' },
    suspended: { label: 'Suspendu',  cls: 'text-amber-700 bg-amber-50 border-amber-200' },
    revoked:   { label: 'Révoqué',   cls: 'text-red-600 bg-red-50 border-red-200' },
  };
  const cfg = CONFIG[status] ?? CONFIG.invited;
  return (
    <span className={`inline-flex items-center rounded-full text-xs font-600 px-2.5 py-1 border ${cfg.cls}`}>
      {cfg.label}
    </span>
  );
}

// ─── Invite Member Modal ──────────────────────────────────────────────────────

interface InviteModalProps {
  organizationId: string;
  onClose: () => void;
  onInvited: () => void;
}

function InviteModal({ organizationId, onClose, onInvited }: InviteModalProps) {
  const [email, setEmail] = useState('');
  const [role, setRole] = useState<'admin' | 'membre'>('membre');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [inviteLink, setInviteLink] = useState<string | null>(null);
  const [copied, setCopied] = useState(false);

  const appUrl = process.env.NEXT_PUBLIC_APP_URL || process.env.NEXT_PUBLIC_SITE_URL || '';

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim()) { setError("L'adresse e-mail est obligatoire."); return; }
    setSaving(true);
    setError('');

    const supabase = createClient();

    // Insert into invitations — RLS: is_organization_owner(organization_id)
    const { data, error: insertError } = await supabase
      .from('invitations')
      .insert({
        organization_id: organizationId,
        email: email.trim().toLowerCase(),
        role,
      })
      .select('token')
      .single();

    setSaving(false);

    if (insertError) {
      setError(insertError.message);
      return;
    }

    const token = data?.token;
    if (token) {
      setInviteLink(`${appUrl}/invitation/${token}`);
      onInvited();
    }
  };

  const handleCopy = () => {
    if (!inviteLink) return;
    navigator.clipboard.writeText(inviteLink).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-base font-700 text-foreground">Inviter un membre</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>

        {inviteLink ? (
          <div className="p-5 space-y-4">
            <div className="rounded-lg bg-green-50 border border-green-200 p-3 flex items-start gap-2">
              <Icon name="CheckCircleIcon" size={16} className="text-green-600 mt-0.5 flex-shrink-0" />
              <p className="text-sm text-green-700">
                Invitation créée pour <strong>{email}</strong>. Copiez le lien ci-dessous et transmettez-le manuellement.
              </p>
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Lien d'invitation</label>
              <div className="flex gap-2">
                <input
                  readOnly
                  value={inviteLink}
                  className="input w-full text-xs font-mono bg-muted"
                />
                <button
                  type="button"
                  onClick={handleCopy}
                  className="btn-primary px-3 py-2 rounded-lg text-sm font-600 flex-shrink-0 flex items-center gap-1.5"
                >
                  <Icon name={copied ? 'CheckIcon' : 'ClipboardDocumentIcon'} size={14} />
                  {copied ? 'Copié !' : 'Copier'}
                </button>
              </div>
              <p className="text-xs text-muted-foreground mt-1.5">
                Aucun e-mail n'est envoyé automatiquement — transmettez ce lien directement à la personne invitée.
              </p>
            </div>
            <div className="flex justify-end pt-1">
              <button onClick={onClose} className="btn-ghost px-4 py-2 rounded-lg text-sm font-600">
                Fermer
              </button>
            </div>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="p-5 space-y-4">
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">
                Adresse e-mail <span className="text-red-500">*</span>
              </label>
              <input
                type="email"
                className="input w-full"
                placeholder="prenom.nom@exemple.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
              />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Rôle</label>
              <select
                className="input w-full"
                value={role}
                onChange={(e) => setRole(e.target.value as 'admin' | 'membre')}
              >
                <option value="membre">Membre</option>
                <option value="admin">Admin</option>
              </select>
            </div>
            {error && (
              <div className="rounded-lg bg-red-50 border border-red-200 px-3 py-2 flex items-start gap-2">
                <Icon name="ExclamationTriangleIcon" size={14} className="text-red-500 mt-0.5 flex-shrink-0" />
                <p className="text-sm text-red-700">{error}</p>
              </div>
            )}
            <div className="flex justify-end gap-3 pt-1">
              <button type="button" onClick={onClose} className="btn-ghost px-4 py-2 rounded-lg text-sm font-600">
                Annuler
              </button>
              <button
                type="submit"
                disabled={saving}
                className="btn-primary px-4 py-2 rounded-lg text-sm font-600 disabled:opacity-50"
              >
                {saving ? 'Envoi…' : 'Créer l\'invitation'}
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}

// ─── Edit Field ───────────────────────────────────────────────────────────────

interface EditFieldProps {
  label: string;
  value: string;
  onSave: (val: string) => Promise<void>;
  type?: 'text' | 'email';
  placeholder?: string;
}

function EditField({ label, value, onSave, type = 'text', placeholder }: EditFieldProps) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(value);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSave = async () => {
    setSaving(true);
    setError('');
    try {
      await onSave(draft.trim());
      setEditing(false);
    } catch (err: any) {
      setError(err?.message ?? 'Erreur lors de la sauvegarde.');
    }
    setSaving(false);
  };

  const handleCancel = () => {
    setDraft(value);
    setEditing(false);
    setError('');
  };

  return (
    <div>
      <label className="block text-xs font-600 text-muted-foreground uppercase tracking-wide mb-1">
        {label}
      </label>
      {editing ? (
        <div className="flex gap-2 items-start">
          <input
            type={type}
            className="input flex-1 text-sm"
            value={draft}
            placeholder={placeholder}
            onChange={(e) => setDraft(e.target.value)}
            autoFocus
          />
          <button
            onClick={handleSave}
            disabled={saving}
            className="btn-primary px-3 py-2 rounded-lg text-sm font-600 disabled:opacity-50 flex-shrink-0"
          >
            {saving ? '…' : 'OK'}
          </button>
          <button
            onClick={handleCancel}
            className="btn-ghost px-3 py-2 rounded-lg text-sm font-600 flex-shrink-0"
          >
            ✕
          </button>
        </div>
      ) : (
        <div className="flex items-center gap-2 group">
          <span className="text-sm text-foreground">
            {value || <span className="text-muted-foreground/60 italic">Non renseigné</span>}
          </span>
          <button
            onClick={() => { setDraft(value); setEditing(true); }}
            className="opacity-0 group-hover:opacity-100 btn-ghost p-1 rounded transition-opacity"
            title="Modifier"
          >
            <Icon name="PencilSquareIcon" size={13} className="text-muted-foreground" />
          </button>
        </div>
      )}
      {error && <p className="text-xs text-red-600 mt-1">{error}</p>}
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function OrganizationDetailPage() {
  const params = useParams();
  const orgId = params?.id as string;

  const [org, setOrg] = useState<Organization | null>(null);
  const [members, setMembers] = useState<OrgMember[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [isOwner, setIsOwner] = useState(false);
  const [showInviteModal, setShowInviteModal] = useState(false);
  const [activeTab, setActiveTab] = useState<'info' | 'members'>('info');

  const fetchData = useCallback(async () => {
    if (!orgId) return;
    setLoading(true);
    setError(null);
    const supabase = createClient();

    const [orgRes, membersRes, ownerRes] = await Promise.all([
      // Query 1: organization fields
      supabase
        .from('organizations')
        .select('id, name, type, neq, address, region, maturity_level, primary_contact_email, status')
        .eq('id', orgId)
        .maybeSingle(),

      // Query 2: members with profiles join
      supabase
        .from('organization_members')
        .select('id, user_id, org_role, operational_profile, status, invited_at, activated_at, profiles(full_name, email)')
        .eq('organization_id', orgId)
        .order('org_role', { ascending: true }),

      // Query 3: check if current user is owner via RPC
      supabase.rpc('is_company_owner', { p_company_id: orgId }),
    ]);

    if (orgRes.error) {
      setError(orgRes.error.message);
      setLoading(false);
      return;
    }

    setOrg(orgRes.data as Organization ?? null);
    setMembers((membersRes.data ?? []) as OrgMember[]);
    setIsOwner(ownerRes.data === true);
    setLoading(false);
  }, [orgId]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const updateField = async (field: keyof Organization, value: string) => {
    const supabase = createClient();
    const { error: updateError } = await supabase
      .from('organizations')
      .update({ [field]: value || null, updated_at: new Date().toISOString() })
      .eq('id', orgId);
    if (updateError) throw new Error(updateError.message);
    setOrg((prev) => prev ? { ...prev, [field]: value || null } : prev);
  };

  if (loading) {
    return (
      <AppLayout>
        <div className="min-h-screen bg-background flex items-center justify-center">
          <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
        </div>
      </AppLayout>
    );
  }

  if (!org) {
    return (
      <AppLayout>
        <div className="min-h-screen bg-background flex items-center justify-center">
          <div className="text-center">
            <Icon name="ExclamationTriangleIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
            <p className="text-muted-foreground">Organisation introuvable.</p>
            <Link href="/organizations" className="text-primary text-sm hover:underline mt-2 inline-block">
              ← Retour à la liste
            </Link>
          </div>
        </div>
      </AppLayout>
    );
  }

  const tabs = [
    { id: 'info', label: 'Informations', icon: 'BuildingOffice2Icon' },
    { id: 'members', label: `Membres (${members.length})`, icon: 'UsersIcon' },
  ] as const;

  return (
    <AppLayout>
      <div className="min-h-screen bg-background">
        <div className="max-w-4xl mx-auto px-4 py-8">

          {/* Breadcrumb + Header */}
          <div className="flex items-start justify-between mb-6 gap-4">
            <div>
              <div className="flex items-center gap-2 text-sm text-muted-foreground mb-1">
                <Link href="/organizations" className="hover:text-primary transition-colors">
                  Organisations
                </Link>
                <Icon name="ChevronRightIcon" size={14} />
                <span className="text-foreground font-500">{org.name}</span>
              </div>
              <div className="flex items-center gap-3">
                <h1 className="text-2xl font-700 text-foreground">{org.name}</h1>
                <OrgStatusBadge status={org.status} />
              </div>
            </div>
          </div>

          {/* Error */}
          {error && (
            <div className="rounded-lg bg-red-50 border border-red-200 px-4 py-3 mb-5 flex items-start gap-2">
              <Icon name="ExclamationTriangleIcon" size={16} className="text-red-500 mt-0.5 flex-shrink-0" />
              <p className="text-sm text-red-700">{error}</p>
            </div>
          )}

          {/* Tabs */}
          <div className="flex gap-1 mb-6 border-b border-border">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-2 px-4 py-2.5 text-sm font-600 border-b-2 transition-colors -mb-px ${
                  activeTab === tab.id
                    ? 'border-primary text-primary' :'border-transparent text-muted-foreground hover:text-foreground'
                }`}
              >
                <Icon name={tab.icon as Parameters<typeof Icon>[0]['name']} size={15} />
                {tab.label}
              </button>
            ))}
          </div>

          {/* Tab: Informations */}
          {activeTab === 'info' && (
            <div className="bg-card rounded-xl border border-border p-6">
              {!isOwner && (
                <div className="rounded-lg bg-muted px-3 py-2 mb-5 flex items-center gap-2">
                  <Icon name="LockClosedIcon" size={14} className="text-muted-foreground" />
                  <p className="text-xs text-muted-foreground">
                    Lecture seule — seul un administrateur de l'organisation peut modifier ces champs.
                  </p>
                </div>
              )}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
                {isOwner ? (
                  <>
                    <EditField
                      label="Nom"
                      value={org.name}
                      onSave={(v) => updateField('name', v)}
                      placeholder="Nom de l'organisation"
                    />
                    <EditField
                      label="Type"
                      value={org.type ?? ''}
                      onSave={(v) => updateField('type', v)}
                      placeholder="ex. OBNL, coopérative…"
                    />
                    <EditField
                      label="NEQ"
                      value={org.neq ?? ''}
                      onSave={(v) => updateField('neq', v)}
                      placeholder="Numéro d'entreprise du Québec"
                    />
                    <EditField
                      label="Région"
                      value={org.region ?? ''}
                      onSave={(v) => updateField('region', v)}
                      placeholder="ex. Montréal, Québec…"
                    />
                    <div className="sm:col-span-2">
                      <EditField
                        label="Adresse"
                        value={org.address ?? ''}
                        onSave={(v) => updateField('address', v)}
                        placeholder="Adresse complète"
                      />
                    </div>
                    <EditField
                      label="Niveau de maturité"
                      value={org.maturity_level ?? ''}
                      onSave={(v) => updateField('maturity_level', v)}
                      placeholder="ex. débutant, intermédiaire…"
                    />
                    <EditField
                      label="Contact principal (e-mail)"
                      value={org.primary_contact_email ?? ''}
                      onSave={(v) => updateField('primary_contact_email', v)}
                      type="email"
                      placeholder="contact@organisation.com"
                    />
                  </>
                ) : (
                  <>
                    <ReadField label="Nom" value={org.name} />
                    <ReadField label="Type" value={org.type} />
                    <ReadField label="NEQ" value={org.neq} />
                    <ReadField label="Région" value={org.region} />
                    <div className="sm:col-span-2">
                      <ReadField label="Adresse" value={org.address} />
                    </div>
                    <ReadField label="Niveau de maturité" value={org.maturity_level} />
                    <ReadField label="Contact principal (e-mail)" value={org.primary_contact_email} />
                  </>
                )}
              </div>
            </div>
          )}

          {/* Tab: Members */}
          {activeTab === 'members' && (
            <div>
              <div className="flex items-center justify-between mb-4">
                <p className="text-sm text-muted-foreground">
                  {members.length} membre{members.length > 1 ? 's' : ''}
                </p>
                {isOwner && (
                  <button
                    onClick={() => setShowInviteModal(true)}
                    className="btn-primary flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-600"
                  >
                    <Icon name="UserPlusIcon" size={15} />
                    Inviter un membre
                  </button>
                )}
              </div>

              <div className="bg-card rounded-xl border border-border overflow-hidden">
                <div className="overflow-x-auto">
                  <table className="w-full text-sm">
                    <thead>
                      <tr className="border-b border-border bg-muted/40">
                        <th className="text-left px-4 py-3 font-600 text-muted-foreground text-xs uppercase tracking-wide">
                          Utilisateur
                        </th>
                        <th className="text-left px-4 py-3 font-600 text-muted-foreground text-xs uppercase tracking-wide hidden sm:table-cell">
                          Rôle org.
                        </th>
                        <th className="text-left px-4 py-3 font-600 text-muted-foreground text-xs uppercase tracking-wide hidden md:table-cell">
                          Profil
                        </th>
                        <th className="text-left px-4 py-3 font-600 text-muted-foreground text-xs uppercase tracking-wide">
                          Statut
                        </th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-border">
                      {members.length === 0 ? (
                        <tr>
                          <td colSpan={4} className="px-4 py-10 text-center text-muted-foreground text-sm">
                            Aucun membre pour l'instant.
                          </td>
                        </tr>
                      ) : (
                        members.map((m) => {
                          const displayName =
                            m.profiles?.full_name ||
                            m.profiles?.email ||
                            m.user_id.slice(0, 8) + '…';
                          return (
                            <tr key={m.id} className="hover:bg-muted/30 transition-colors">
                              <td className="px-4 py-3">
                                <div>
                                  <p className="font-500 text-foreground">{displayName}</p>
                                  {m.profiles?.email && m.profiles?.full_name && (
                                    <p className="text-xs text-muted-foreground">{m.profiles.email}</p>
                                  )}
                                </div>
                              </td>
                              <td className="px-4 py-3 hidden sm:table-cell">
                                <span className={`inline-flex items-center rounded-full text-xs font-600 px-2.5 py-1 border ${
                                  m.org_role === 'admin' ?'text-purple-700 bg-purple-50 border-purple-200' :'text-blue-700 bg-blue-50 border-blue-200'
                                }`}>
                                  {m.org_role === 'admin' ? 'Admin' : 'Membre'}
                                </span>
                              </td>
                              <td className="px-4 py-3 text-muted-foreground hidden md:table-cell capitalize">
                                {m.operational_profile}
                              </td>
                              <td className="px-4 py-3">
                                <MemberStatusBadge status={m.status} />
                              </td>
                            </tr>
                          );
                        })
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            </div>
          )}

        </div>
      </div>

      {showInviteModal && (
        <InviteModal
          organizationId={orgId}
          onClose={() => setShowInviteModal(false)}
          onInvited={fetchData}
        />
      )}
    </AppLayout>
  );
}

// ─── Read-only field ──────────────────────────────────────────────────────────

function ReadField({ label, value }: { label: string; value: string | null }) {
  return (
    <div>
      <label className="block text-xs font-600 text-muted-foreground uppercase tracking-wide mb-1">
        {label}
      </label>
      <p className="text-sm text-foreground">
        {value || <span className="text-muted-foreground/60 italic">Non renseigné</span>}
      </p>
    </div>
  );
}
