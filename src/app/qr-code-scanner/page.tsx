import AppLayout from '@/components/AppLayout';
import QRScannerContent from './components/QRScannerContent';

export default function QRScannerPage() {
  return (
    <AppLayout activeRoute="/qr-code-scanner" userRole="client">
      <QRScannerContent />
    </AppLayout>
  );
}