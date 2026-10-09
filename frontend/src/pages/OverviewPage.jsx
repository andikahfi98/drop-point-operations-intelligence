import { useEffect, useState } from 'react';
import { ArrowUpRight, CalendarDays } from 'lucide-react';
import { api } from '../api';
import { AgeDistribution, MetricStrip, PerformanceTable, PriorityPanel, PulseChart } from '../components/OperationsVisuals';
import { fmt } from '../format';

export default function OverviewPage({ rows, token, onOpen, onUnauthorized }) {
  const [days, setDays] = useState(7);
  const [pulse, setPulse] = useState([]);
  const [pulseError, setPulseError] = useState('');

  useEffect(() => {
    const controller = new AbortController();
    setPulseError('');
    api.pulse(token, days, controller.signal).then((result) => setPulse(result.data || [])).catch((error) => {
      if (error.name === 'AbortError') return;
      if (error.status === 401) onUnauthorized(); else setPulseError(error.message);
    });
    return () => controller.abort();
  }, [token, days, onUnauthorized]);

  const region = rows.length && rows.every((row) => row.region === rows[0].region) ? rows[0].region : 'Semua region';
  return <div className="page-content v2-page"><div className="v2-page-intro"><div><span className="v2-eyebrow">COMMAND CENTER / REGIONAL</span><h1>Operasional {region}</h1><p>Arus paket, kualitas pengiriman, pendapatan, dan prioritas setiap Drop Point.</p></div><div className="v2-asof"><CalendarDays size={18} /><span><strong>{fmt.date(rows[0]?.as_of_date)}</strong><small>Waktu data simulasi · {fmt.number(rows.length)} DP dalam akses Anda</small></span></div></div>
    <div className="v2-top-grid"><div>{pulseError && <p className="v2-inline-error">Riwayat belum dapat dimuat: {pulseError}</p>}<PulseChart rows={pulse} days={days} onDaysChange={setDays} /></div><PriorityPanel rows={rows} onSelect={(item) => onOpen(item.drop_point_id)} /></div>
    <MetricStrip rows={rows} />
    <div className="v2-bottom-grid"><PerformanceTable rows={rows} onOpen={onOpen} /><div className="v2-side-stack"><AgeDistribution rows={rows} /><button type="button" className="v2-explore-link" onClick={() => rows[0] && onOpen(rows[0].drop_point_id)}>Jelajahi detail Drop Point <ArrowUpRight size={18} /></button></div></div>
  </div>;
}
