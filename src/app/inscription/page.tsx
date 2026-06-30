'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/client';
import AppLogo from '@/components/ui/AppLogo';

export default function InscriptionPage() {
  const router = useRouter();
  const [companyName, setCompanyName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);

    const supabase = createClient();

    try {
      // Step 1: Create Supabase Auth account
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email,
        password,
      });

      if (authError) {
        setError(authError.message);
        setLoading(false);
        return;
      }

      const userId = authData?.user?.id;
      if (!userId) {
        setError("La création du compte a échoué. Veuillez réessayer.");
        setLoading(false);
        return;
      }

      // Step 2: Insert into companies table
      const { data: companyData, error: companyError } = await supabase
        .from('companies')
        .insert({ name: companyName.trim() })
        .select('id')
        .single();

      if (companyError || !companyData) {
        setError(
          `Votre compte a été créé, mais l'enregistrement de l'entreprise a échoué : ${companyError?.message ?? 'erreur inconnue'}. Veuillez contacter le support.`
        );
        setLoading(false);
        return;
      }

      const companyId = companyData.id;

      // Step 3: Insert into company_members as owner
      const { error: memberError } = await supabase.from('company_members').insert({
        company_id: companyId,
        user_id: userId,
        role: 'owner',
      });

      if (memberError) {
        setError(
          `Votre compte et votre entreprise ont été créés, mais l'attribution du rôle propriétaire a échoué : ${memberError.message}. Veuillez contacter le support.`
        );
        setLoading(false);
        return;
      }

      // Success — redirect to client dashboard
      router.push('/');
    } catch (err: any) {
      setError(err?.message ?? "Une erreur inattendue s'est produite.");
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-background flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md">
        {/* Logo */}
        <div className="flex flex-col items-center mb-8">
          <AppLogo size={48} />
          <h1 className="mt-4 text-2xl font-bold text-foreground tracking-tight">
            Créer votre compte entreprise
          </h1>
          <p className="mt-1 text-sm text-muted-foreground text-center">
            Inscrivez votre entreprise sur METALTRACE
          </p>
        </div>

        {/* Form Card */}
        <div className="bg-card border border-border rounded-xl p-8 shadow-sm">
          <form onSubmit={handleSubmit} className="space-y-5">
            {/* Company Name */}
            <div>
              <label
                htmlFor="companyName"
                className="block text-sm font-medium text-foreground mb-1.5"
              >
                Nom de l&apos;entreprise
              </label>
              <input
                id="companyName"
                type="text"
                required
                value={companyName}
                onChange={(e) => setCompanyName(e.target.value)}
                placeholder="Ex. : Récupération Dupont inc."
                className="w-full px-3 py-2.5 rounded-lg border border-border bg-background text-foreground placeholder:text-muted-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent transition"
              />
            </div>

            {/* Email */}
            <div>
              <label
                htmlFor="email"
                className="block text-sm font-medium text-foreground mb-1.5"
              >
                Adresse courriel
              </label>
              <input
                id="email"
                type="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="vous@entreprise.com"
                className="w-full px-3 py-2.5 rounded-lg border border-border bg-background text-foreground placeholder:text-muted-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent transition"
              />
            </div>

            {/* Password */}
            <div>
              <label
                htmlFor="password"
                className="block text-sm font-medium text-foreground mb-1.5"
              >
                Mot de passe
              </label>
              <input
                id="password"
                type="password"
                required
                minLength={8}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Minimum 8 caractères"
                className="w-full px-3 py-2.5 rounded-lg border border-border bg-background text-foreground placeholder:text-muted-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary focus:border-transparent transition"
              />
            </div>

            {/* Error message */}
            {error && (
              <div className="rounded-lg bg-destructive/10 border border-destructive/20 px-4 py-3">
                <p className="text-sm text-destructive">{error}</p>
              </div>
            )}

            {/* Submit */}
            <button
              type="submit"
              disabled={loading || !companyName.trim() || !email || !password}
              className="w-full py-2.5 px-4 rounded-lg bg-primary text-primary-foreground text-sm font-semibold hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed transition"
            >
              {loading ? (
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
                  Création en cours…
                </span>
              ) : (
                'Créer mon compte'
              )}
            </button>
          </form>
        </div>

        {/* Footer link */}
        <p className="mt-6 text-center text-sm text-muted-foreground">
          Déjà un compte ?{' '}
          <Link href="/login" className="text-primary font-medium hover:underline">
            Se connecter
          </Link>
        </p>
      </div>
    </div>
  );
}
