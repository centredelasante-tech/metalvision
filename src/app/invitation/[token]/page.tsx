'use client';

import { useState, useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import AppLogo from '@/components/ui/AppLogo';

interface InvitationData {
  invitation_id: string;
  organization_id: string;
  organization_name: string;
  email: string;
  role: string;
  status: string;
  expires_at: string;
}

type PageState = 'loading' | 'invalid' | 'form' | 'submitting' | 'error';

const ROLE_LABELS: Record<string, string> = {
  owner: 'Propriétaire',
  terrain: 'Employé terrain',
};

export default function InvitationPage() {
  const params = useParams();
  const router = useRouter();
  const token = params?.token as string;

  const [pageState, setPageState] = useState<PageState>('loading');
  const [invitation, setInvitation] = useState<InvitationData | null>(null);
  const [invalidReason, setInvalidReason] = useState<string>('');
  const [password, setPassword] = useState('');
  const [submitError, setSubmitError] = useState<string | null>(null);

  useEffect(() => {
    if (!token) {
      setInvalidReason("Lien d'invitation invalide ou manquant.");
      setPageState('invalid');
      return;
    }

    const fetchInvitation = async () => {
      const supabase = createClient();

      // Call the SECURITY DEFINER RPC — callable by anon
      const { data, error } = await supabase.rpc('get_invitation_by_token', {
        p_token: token,
      });

      if (error) {
        setInvalidReason(
          "Une erreur s'est produite lors de la vérification de l'invitation. Veuillez réessayer."
        );
        setPageState('invalid');
        return;
      }

      if (!data || data.length === 0) {
        // Token not found, expired, or already accepted — check which
        // We do a second query to distinguish (authenticated or not)
        setInvalidReason(
          "Ce lien d'invitation est invalide, expiré ou a déjà été accepté. Veuillez demander un nouveau lien à votre administrateur."
        );
        setPageState('invalid');
        return;
      }

      setInvitation(data[0] as InvitationData);
      setPageState('form');
    };

    fetchInvitation();
  }, [token]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!invitation) return;

    setSubmitError(null);
    setPageState('submitting');

    const supabase = createClient();

    try {
      // Step 1: Sign up or sign in with the invitation email
      let userId: string | null = null;

      const { data: signUpData, error: signUpError } = await supabase.auth.signUp({
        email: invitation.email,
        password,
      });

      if (signUpError) {
        // If user already exists, try signing in
        if (
          signUpError.message.toLowerCase().includes('already registered') ||
          signUpError.message.toLowerCase().includes('already exists') ||
          signUpError.message.toLowerCase().includes('user already')
        ) {
          const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
            email: invitation.email,
            password,
          });

          if (signInError) {
            setSubmitError(
              `Connexion échouée : ${signInError.message}. Vérifiez votre mot de passe.`
            );
            setPageState('form');
            return;
          }

          userId = signInData?.user?.id ?? null;
        } else {
          setSubmitError(`Création du compte échouée : ${signUpError.message}`);
          setPageState('form');
          return;
        }
      } else {
        userId = signUpData?.user?.id ?? null;
      }

      if (!userId) {
        setSubmitError("Impossible d'obtenir l'identifiant utilisateur. Veuillez réessayer.");
        setPageState('form');
        return;
      }

      // Step 2: Insert into organization_members
      const { error: memberError } = await supabase.from('organization_members').insert({
        organization_id: invitation.organization_id,
        user_id: userId,
        org_role: invitation.role,
        status: 'active',
      });

      if (memberError) {
        // If already a member (unique constraint), continue to accept invitation
        if (!memberError.message.includes('unique') && !memberError.message.includes('duplicate')) {
          setSubmitError(
            `Erreur lors de l'ajout à l'organisation : ${memberError.message}. Veuillez contacter le support.`
          );
          setPageState('form');
          return;
        }
      }

      // Step 3: Mark invitation as accepted
      const { error: updateError } = await supabase
        .from('invitations')
        .update({
          status: 'accepted',
          accepted_at: new Date().toISOString(),
        })
        .eq('id', invitation.invitation_id);

      if (updateError) {
        // Non-blocking: log but don't fail the flow
        console.warn('Could not update invitation status:', updateError.message);
      }

      // Step 4: Redirect based on role
      router.push('/');
    } catch (err: any) {
      setSubmitError(err?.message ?? "Une erreur inattendue s'est produite.");
      setPageState('form');
    }
  };

  const roleLabel = invitation ? (ROLE_LABELS[invitation.role] ?? invitation.role) : '';

  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md">
        {/* Logo */}
        <div className="flex flex-col items-center mb-8">
          <AppLogo size={48} />
          <h1 className="mt-4 text-2xl font-bold text-foreground tracking-tight">
            Invitation METALTRACE
          </h1>
        </div>

        {/* Loading */}
        {pageState === 'loading' && (
          <div className="bg-card border border-border rounded-xl p-8 shadow-sm flex flex-col items-center gap-4">
            <svg
              className="animate-spin h-8 w-8 text-primary"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                className="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                strokeWidth="4"
              />
              <path
                className="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
              />
            </svg>
            <p className="text-sm text-muted-foreground">Vérification de l&apos;invitation…</p>
          </div>
        )}

        {/* Invalid / expired / already accepted */}
        {pageState === 'invalid' && (
          <div className="bg-card border border-border rounded-xl p-8 shadow-sm">
            <div className="flex flex-col items-center gap-4 text-center">
              <div className="w-12 h-12 rounded-full bg-destructive/10 flex items-center justify-center">
                <svg
                  className="w-6 h-6 text-destructive"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke="currentColor"
                  strokeWidth={2}
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"
                  />
                </svg>
              </div>
              <div>
                <h2 className="text-lg font-semibold text-foreground mb-2">
                  Invitation non valide
                </h2>
                <p className="text-sm text-muted-foreground">{invalidReason}</p>
              </div>
            </div>
          </div>
        )}

        {/* Form */}
        {(pageState === 'form' || pageState === 'submitting') && invitation && (
          <div className="bg-card border border-border rounded-xl p-8 shadow-sm">
            {/* Invitation info banner */}
            <div className="rounded-lg bg-primary/5 border border-primary/20 px-4 py-3 mb-6">
              <p className="text-sm text-foreground">
                Vous êtes invité(e) à rejoindre{' '}
                <span className="font-semibold">{invitation.organization_name}</span> en tant que{' '}
                <span className="font-semibold">{roleLabel}</span>.
              </p>
            </div>

            <form onSubmit={handleSubmit} className="space-y-5">
              {/* Email (pre-filled, read-only) */}
              <div>
                <label
                  htmlFor="inv-email"
                  className="block text-sm font-medium text-foreground mb-1.5"
                >
                  Adresse courriel
                </label>
                <input
                  id="inv-email"
                  type="email"
                  value={invitation.email}
                  readOnly
                  disabled
                  className="w-full px-3 py-2.5 rounded-lg border border-border bg-muted text-muted-foreground text-sm cursor-not-allowed"
                />
              </div>

              {/* Password */}
              <div>
                <label
                  htmlFor="inv-password"
                  className="block text-sm font-medium text-foreground mb-1.5"
                >
                  Choisissez un mot de passe
                </label>
                <input
                  id="inv-password"
                  type="password"
                  required
                  minLength={8}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Minimum 8 caractères"
                  disabled={pageState === 'submitting'}
                  className="w-full px-3 py-2.5 rounded-lg border border-border bg-background text-foreground placeholder:text-muted-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent transition disabled:opacity-50"
                />
                <p className="mt-1 text-xs text-muted-foreground">
                  Si vous avez déjà un compte avec cet email, entrez votre mot de passe existant.
                </p>
              </div>

              {/* Error */}
              {submitError && (
                <div className="rounded-lg bg-destructive/10 border border-destructive/20 px-4 py-3">
                  <p className="text-sm text-destructive">{submitError}</p>
                </div>
              )}

              {/* Submit */}
              <button
                type="submit"
                disabled={pageState === 'submitting' || !password}
                className="w-full py-2.5 px-4 rounded-lg bg-primary text-primary-foreground text-sm font-semibold hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition"
              >
                {pageState === 'submitting' ? (
                  <span className="flex items-center justify-center gap-2">
                    <svg
                      className="animate-spin h-4 w-4"
                      xmlns="http://www.w3.org/2000/svg"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <circle
                        className="opacity-25"
                        cx="12"
                        cy="12"
                        r="10"
                        stroke="currentColor"
                        strokeWidth="4"
                      />
                      <path
                        className="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                      />
                    </svg>
                    Activation en cours…
                  </span>
                ) : (
                  'Accepter l\'invitation'
                )}
              </button>
            </form>
          </div>
        )}
      </div>
    </div>
  );
}
