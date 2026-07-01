'use client';
import React, { useState } from 'react';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import type { ContainerData } from './QRScannerContent';

interface ManualEntryProps {
  onResult: (container: ContainerData | null, error: string | null) => void;
}

export default function ManualEntry({ onResult }: ManualEntryProps) {
  const { user } = useAuth();
  const [code, setCode] = useState('');
  const [loading, setLoading] = useState(false);
  const [inputError, setInputError] = useState<string | null>(null);

  const handleSearch = async () => {
    const trimmed = code.trim();
    if (!trimmed) {
      setInputError('Veuillez saisir un code QR.');
      return;
    }
    setInputError(null);
    setLoading(true);

    const supabase = createClient();

    // Get user's company_id
    const { data: memberData } = await supabase
      .from('company_members')
      .select('company_id')
      .eq('user_id', user?.id)
      .limit(1)
      .single();

    const userCompanyId = memberData?.company_id ?? null;

    // Query container
    const { data: containers, error } = await supabase
      .from('containers')
      .select('id, name, location, status, company_id, qr_code')
      .eq('qr_code', trimmed)
      .eq('status', 'active')
      .limit(1);

    setLoading(false);

    if (error || !containers || containers.length === 0) {
      onResult(null, 'Conteneur introuvable ou inactif. Vérifiez le code et réessayez.');
      return;
    }

    const container = containers[0] as ContainerData;

    if (userCompanyId && container.company_id !== userCompanyId) {
      onResult(null, 'Ce conteneur appartient à une autre entreprise. Vous n\'êtes pas autorisé à y accéder.');
      return;
    }

    onResult(container, null);
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') handleSearch();
  };

  return (
    <div className="bg-card rounded-xl border border-border p-5">
      <div className="flex items-center gap-2 mb-1">
        <Icon name="PencilSquareIcon" size={18} className="text-primary" />
        <h3 className="text-base font-600 text-foreground">Saisie manuelle</h3>
      </div>
      <p className="text-xs text-muted-foreground mb-5">
        Entrez le code QR inscrit sur le conteneur (ex : QR-CT-001, CT-003)
      </p>

      <div className="space-y-3">
        <div>
          <label className="text-xs font-600 text-muted-foreground uppercase tracking-wide mb-1.5 block">
            Code QR du conteneur
          </label>
          <div className="flex gap-3">
            <div className="flex-1 relative">
              <div className="absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none">
                <Icon name="QrCodeIcon" size={16} className="text-muted-foreground" />
              </div>
              <input
                type="text"
                value={code}
                onChange={(e) => { setCode(e.target.value); setInputError(null); }}
                onKeyDown={handleKeyDown}
                placeholder="QR-CT-001"
                className="w-full pl-9 pr-4 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm font-500 focus:outline-none focus:ring-2 focus:ring-ring placeholder:text-muted-foreground"
                autoComplete="off"
                autoCapitalize="characters"
              />
            </div>
            <button
              type="button"
              onClick={handleSearch}
              disabled={loading}
              className="px-5 py-2.5 rounded-lg text-sm font-600 btn-primary flex items-center gap-2 min-h-[44px] disabled:opacity-60"
            >
              {loading ? (
                <div className="w-4 h-4 border-2 border-primary-foreground/30 border-t-primary-foreground rounded-full animate-spin" />
              ) : (
                <Icon name="MagnifyingGlassIcon" size={16} className="text-primary-foreground" />
              )}
              <span className="hidden sm:inline">{loading ? 'Recherche…' : 'Rechercher'}</span>
            </button>
          </div>
          {inputError && (
            <p className="text-xs text-red-600 mt-1.5 flex items-center gap-1">
              <Icon name="ExclamationCircleIcon" size={12} />
              {inputError}
            </p>
          )}
        </div>

        <p className="text-[11px] text-muted-foreground">
          Le code est généralement imprimé sous le QR code sur l'étiquette du conteneur.
        </p>
      </div>
    </div>
  );
}