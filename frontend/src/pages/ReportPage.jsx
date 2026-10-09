import { useEffect, useMemo, useState } from 'react';
import { Download } from 'lucide-react';
import { api } from '../api';
import { EmptyState, ErrorState, LoadingState, SearchFilters, StatusBadge } from '../components/Ui';
import { csvDownload, fmt } from '../format';

const exportColumns = [
  ['Tanggal', 'business_date'], ['Drop Point', 'drop_point_name'], ['Pendapatan harian', 'daily_revenue'],
  ['Paket masuk', 'daily_parcel_in'], ['Paket keluar', 'daily_parcel_out'], ['Paket di DP', 'parcel_at_dp'],
  ['Paket >24 jam', 'parcel_over_24h'], ['Pengiriman', 'daily_shipment'], ['Tepat waktu', 'daily_on_time'],
  ['SLA MTD', 'mtd_on_time_rate_pct'], ['Status', 'overall_status'],
];

export default function ReportPage({ token, onOpen, onUnauthorized, summaryRows }) {
  const [report, setReport] = useState(null);
  const [error, setError] = useState('');
  const [query, setQuery] = useState('');
  const [region, setRegion] = useState('ALL');
  const [status, setStatus] = useState('ALL');
  const [refresh, setRefresh] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    setError('');
    api.dailyReport(token, controller.signal).then(setReport).catch((failure) => {
      if (failure.name === 'AbortError') return;
      if (failure.status === 401) onUnauthorized(); else setError(failure.message);
    });
    return () => controller.abort();
  }, [token, refresh, onUnauthorized]);
  const regionById = Object.fromEntries(summaryRows.map((row) => [row.drop_point_id, row.region]));
  const rows = (report?.data || []).map((row) => ({ ...row, region: regionById[row.drop_point_id] }));
  const regions = useMemo(() => [...new Set(rows.map((row) => row.region).filter(Boolean))].sort(), [rows]);
  const filtered = rows.filter((row) => (region === 'ALL' || row.region === region) && (status === 'ALL' || row.overall_status === status) && row.drop_point_name?.toLocaleLowerCase('id-ID').includes(query.toLocaleLowerCase('id-ID')));

  return <div className="page-content"><div className="page-title page-title-with-action"><div><h1>Laporan harian</h1><p>Ringkasan per Drop Point untuk {fmt.date(report?.business_date)}.</p></div><button type="button" className="outline-button" disabled={!filtered.length} onClick={() => csvDownload(`laporan-drop-point-${String(report?.business_date || 'harian').slice(0, 10)}.csv`, filtered, exportColumns)}><Download size={17} /> Unduh CSV</button></div>
    {error ? <ErrorState message={error} onRetry={() => setRefresh((value) => value + 1)} /> : !report ? <LoadingState /> : <section className="table-panel"><div className="table-panel-heading"><div><h2>Aktivitas Drop Point</h2><p>Klik nama Drop Point untuk melihat rincian.</p></div></div><SearchFilters query={query} onQuery={setQuery} region={region} onRegion={setRegion} status={status} onStatus={setStatus} regions={regions} count={filtered.length} />
      {filtered.length ? <div className="table-scroll"><table className="data-table report-table"><thead><tr><th>Drop Point</th><th>Pendapatan</th><th>Paket masuk</th><th>Paket keluar</th><th>Paket di DP</th><th>&gt; 24 jam</th><th>Pengiriman</th><th>SLA MTD</th><th>Status</th></tr></thead><tbody>{filtered.map((row) => <tr key={row.drop_point_id}><td data-label="Drop Point"><button className="row-link" type="button" onClick={() => onOpen(row.drop_point_id)}>{row.drop_point_name}</button></td><td data-label="Pendapatan">{fmt.money(row.daily_revenue)}</td><td data-label="Paket masuk">{fmt.number(row.daily_parcel_in)}</td><td data-label="Paket keluar">{fmt.number(row.daily_parcel_out)}</td><td data-label="Paket di DP">{fmt.number(row.parcel_at_dp)}</td><td data-label="> 24 jam">{fmt.number(row.parcel_over_24h)}</td><td data-label="Pengiriman">{fmt.number(row.daily_shipment)}</td><td data-label="SLA MTD">{fmt.percent(row.mtd_on_time_rate_pct)}</td><td data-label="Status"><StatusBadge status={row.overall_status} /></td></tr>)}</tbody></table></div> : <EmptyState title="Tidak ada laporan yang cocok" message="Ubah pencarian atau filter untuk melihat data lain." />}</section>}
  </div>;
}
