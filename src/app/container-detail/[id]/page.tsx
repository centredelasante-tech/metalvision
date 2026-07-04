import AppLayout from '@/components/AppLayout';
import ContainerDetailContent from '../components/ContainerDetailContent';
import { createClient } from '@/lib/supabase/server';

interface ContainerDetailPageProps {
  params: Promise<{ id: string }>;
}

export default async function ContainerDetailPage({ params }: ContainerDetailPageProps) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: container } = await supabase
    .from('containers')
    .select('*')
    .eq('id', id)
    .single();

  return (
    <AppLayout activeRoute="/container-detail" userRole="admin">
      <ContainerDetailContent container={container} />
    </AppLayout>
  );
}
