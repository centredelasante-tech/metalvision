'use client';
import React, { useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';

export default function NewOrganizationPage() {
  const router = useRouter();

  const [name, setName] = useState('');
  const [type, setType] = useState('');
  const [region, setRegion] = useState('');
  const [neq, setNeq] = useState('');
  const [address, setAddress] = useState('');
  const [maturityLevel, setMaturityLevel] = useState('');
  const [primaryContactEmail, setPrimaryContactEmail] = useState('');

  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim()) { setError('Le nom est obligatoire.'); return; }

    setSaving(true);
    setError(null);

    const supabase = createClient();

    // Insert organization — status defaults to 'active' (DB default), not exposed in form
    const { data, error: insertError } = await supabase
      .from('organizations')
      .insert({
        name: name.trim(),
        type: type.trim() || null,
        region: region.trim() || null,
        neq: neq.trim() || null,
        address: address.trim() || null,
        maturity_level: maturityLevel.trim() || null,
        primary_contact_email: primaryContactEmail.trim() || null,
      })
      .select('id')
      .single();

    setSaving(false);

    if (insertError) {
      setError(insertError.message);
      return;
    }

    router.push(`/organizations/${data.id}`);
  };

  return (
    <AppLayout>
      <div className="min-h-screen bg-background">
        <div className="max-w-2xl mx-auto px-4 py-8">

          {/* Breadcrumb */}
          <div className="flex items-center gap-2 text-sm text-muted-foreground mb-6">
            <Link href="/organizations" className="hover:text-primary transition-colors">
              Organisations
            </Link>
            <Icon name="ChevronRightIcon" size={14} />
            <span className="text-foreground font-500">Nouvelle organisation</span>
          </div>

          <div className="bg-card rounded-xl border border-border p-6">
            <div className="mb-6">
              <h1 className="text-xl font-700 text-foreground">Nouvelle organisation</h1>
              <p className="text-sm text-muted-foreground mt-1">
                Seul le nom est requis. Tous les autres champs peuvent être complétés ultérieurement.
              </p>
            </div>

            <form onSubmit={handleSubmit} className="space-y-5">

              {/* Name — required */}
              <div>
                <label className="block text-sm font-600 text-foreground mb-1">
                  Nom de l'organisation <span className="text-red-500">*</span>
                </label>
                <input
                  type="text"
                  className="input w-full"
                  placeholder="ex. Récupération Montréal inc."
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  required
                  autoFocus
                />
              </div>

              {/* Optional fields */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-600 text-foreground mb-1">
                    Type <span className="text-xs text-muted-foreground font-400">(optionnel)</span>
                  </label>
                  <input
                    type="text"
                    className="input w-full"
                    placeholder="ex. OBNL, coopérative…"
                    value={type}
                    onChange={(e) => setType(e.target.value)}
                  />
                </div>
                <div>
                  <label className="block text-sm font-600 text-foreground mb-1">
                    Région <span className="text-xs text-muted-foreground font-400">(optionnel)</span>
                  </label>
                  <input
                    type="text"
                    className="input w-full"
                    placeholder="ex. Montréal, Québec…"
                    value={region}
                    onChange={(e) => setRegion(e.target.value)}
                  />
                </div>
                <div>
                  <label className="block text-sm font-600 text-foreground mb-1">
                    NEQ <span className="text-xs text-muted-foreground font-400">(optionnel)</span>
                  </label>
                  <input
                    type="text"
                    className="input w-full"
                    placeholder="Numéro d'entreprise du Québec"
                    value={neq}
                    onChange={(e) => setNeq(e.target.value)}
                  />
                </div>
                <div>
                  <label className="block text-sm font-600 text-foreground mb-1">
                    Niveau de maturité <span className="text-xs text-muted-foreground font-400">(optionnel)</span>
                  </label>
                  <input
                    type="text"
                    className="input w-full"
                    placeholder="ex. débutant, intermédiaire…"
                    value={maturityLevel}
                    onChange={(e) => setMaturityLevel(e.target.value)}
                  />
                </div>
                <div className="sm:col-span-2">
                  <label className="block text-sm font-600 text-foreground mb-1">
                    Adresse <span className="text-xs text-muted-foreground font-400">(optionnel)</span>
                  </label>
                  <input
                    type="text"
                    className="input w-full"
                    placeholder="Adresse complète"
                    value={address}
                    onChange={(e) => setAddress(e.target.value)}
                  />
                </div>
                <div className="sm:col-span-2">
                  <label className="block text-sm font-600 text-foreground mb-1">
                    Contact principal (e-mail) <span className="text-xs text-muted-foreground font-400">(optionnel)</span>
                  </label>
                  <input
                    type="email"
                    className="input w-full"
                    placeholder="contact@organisation.com"
                    value={primaryContactEmail}
                    onChange={(e) => setPrimaryContactEmail(e.target.value)}
                  />
                </div>
              </div>

              {/* Error */}
              {error && (
                <div className="rounded-lg bg-red-50 border border-red-200 px-4 py-3 flex items-start gap-2">
                  <Icon name="ExclamationTriangleIcon" size={16} className="text-red-500 mt-0.5 flex-shrink-0" />
                  <p className="text-sm text-red-700">{error}</p>
                </div>
              )}

              {/* Actions */}
              <div className="flex justify-end gap-3 pt-2">
                <Link
                  href="/organizations"
                  className="btn-ghost px-4 py-2.5 rounded-lg text-sm font-600"
                >
                  Annuler
                </Link>
                <button
                  type="submit"
                  disabled={saving || !name.trim()}
                  className="btn-primary px-5 py-2.5 rounded-lg text-sm font-600 disabled:opacity-50 flex items-center gap-2"
                >
                  {saving ? (
                    <>
                      <div className="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin" />
                      Création…
                    </>
                  ) : (
                    <>
                      <Icon name="PlusIcon" size={15} />
                      Créer l'organisation
                    </>
                  )}
                </button>
              </div>
            </form>
          </div>

        </div>
      </div>
    </AppLayout>
  );
}
