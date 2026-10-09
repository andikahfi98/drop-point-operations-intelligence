import { useEffect, useMemo, useState } from 'react';
import { ArrowLeft, ArrowUpRight, CalendarDays, ChevronRight, Clock3, Search } from 'lucide-react';
import { api } from '../api';
import { AgeDistribution, MetricStrip, PanelHeading, PriorityPanel, PulseChart } from '../components/OperationsVisuals';
import { EmptyState, ErrorState, LoadingState, StatusBadge } from '../components/Ui';
import { fmt } from '../format';

const tabs = [
  ['operations', 'Operasi'], ['parcels', 'Paket'], ['delivery', 'Pengiriman'],
  ['sellers', 'Seller & Pendapatan'], ['seller-pics', 'PIC Seller'],
  ['team', 'Tim & Tanggung Jawab'],
];
const sectionsToLoad = ['parcels', 'delivery', 'sellers', 'seller-pics', 'team', 'responsibility'];

function ProgressMeter({ value, target = 100, label, tone = 'red' }) {
  const amount = Number(value || 0);
  return <div className="v2-progress"><div><span>{label}</span><strong>{fmt.percent(value)} <small>/ {fmt.percent(target)}</small></strong></div><div className="v2-progress-track"><span className={`v2-progress-${tone}`} style={{ width: `${Math.max(0, Math.min(100, amount))}%` }} /></div></div>;
}

function QuickNumber({ label, value, note }) {
  return <div className="v2-quick-number"><span>{label}</span><strong>{value}</strong>{note && <small>{note}</small>}</div>;
}

function IssueTable({ issues = [], type }) {
  const [query, setQuery] = useState('');
  const filtered = issues.filter((row) => `${row.invoice_id} ${row.shipment_id} ${row.seller_name} ${row.parcel_issue_reason} ${row.delivery_issue_reason} ${row.responsible_unit_name}`.toLowerCase().includes(query.toLowerCase()));
  return <section className="v2-panel v2-data-panel"><PanelHeading title={type === 'parcels' ? 'Paket yang perlu ditangani' : 'Pengiriman yang perlu ditangani'} description={`${fmt.number(issues.length)} isu aktif yang tersedia · urutan dari data operasional`} action={<label className="v2-search"><Search size={16} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Cari resi, seller, alasan" aria-label="Cari isu" /></label>} />
    {filtered.length ? <div className="v2-table-scroll"><table className="v2-data-table"><thead><tr><th>Resi / seller</th><th>Status</th><th>Alasan</th><th>Durasi</th><th>Penanggung jawab</th></tr></thead><tbody>{filtered.map((row) => <tr key={`${row.shipment_id}-${row.issue_type}`}><td><strong>{row.invoice_id || row.shipment_id}</strong><small>{row.seller_name || '—'}</small></td><td>{row.issue_type || row.shipment_status || '—'}</td><td>{type === 'parcels' ? row.parcel_issue_reason || '—' : row.delivery_issue_reason || '—'}</td><td><strong>{fmt.decimal(row.issue_hours)} jam</strong></td><td>{row.responsible_staff_name || row.responsible_unit_name || 'Belum ditetapkan'}</td></tr>)}</tbody></table></div> : <EmptyState title={query ? 'Isu tidak ditemukan' : 'Tidak ada isu aktif'} message={query ? 'Coba kata pencarian lain.' : 'Tidak ada daftar isu pada kategori ini saat data diambil.'} />}</section>;
}

function ParcelQueue({ rows = [], count = 0 }) {
  const [query, setQuery] = useState('');
  const [stage, setStage] = useState('ALL');
  const [showAll, setShowAll] = useState(false);
  const stages = [...new Set(rows.map((row) => row.shipment_status).filter(Boolean))].sort();
  const filtered = rows.filter((row) => (stage === 'ALL' || row.shipment_status === stage) && `${row.invoice_id} ${row.seller_name} ${row.origin_dp_name} ${row.destination_dp_name}`.toLowerCase().includes(query.toLowerCase()));
  const shown = showAll ? filtered : filtered.slice(0, 20);
  return <section className="v2-panel v2-data-panel"><PanelHeading title="Paket saat ini di DP" description={`${fmt.number(count)} paket fisik · maksimal 100 resi ditampilkan, usia tertua lebih dulu`} action={<div className="v2-table-controls"><label className="v2-search"><Search size={16} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Cari resi atau seller" aria-label="Cari paket saat ini" /></label><select value={stage} onChange={(event) => setStage(event.target.value)} aria-label="Filter tahap paket"><option value="ALL">Semua tahap</option>{stages.map((item) => <option value={item} key={item}>{item.replaceAll('_', ' ')}</option>)}</select></div>} />
    {shown.length ? <><div className="v2-table-scroll"><table className="v2-data-table"><thead><tr><th>Resi / seller</th><th>Tahap</th><th>Asal → tujuan</th><th>Sejak di DP</th><th>Usia</th></tr></thead><tbody>{shown.map((row) => <tr key={row.shipment_id}><td><strong>{row.invoice_id || row.shipment_id}</strong><small>{row.seller_name || '—'}</small></td><td>{row.shipment_status?.replaceAll('_', ' ') || '—'}</td><td>{row.origin_dp_name || '—'} <ChevronRight size={13} /> {row.destination_dp_name || '—'}</td><td>{row.at_dp_since_ts ? fmt.date(row.at_dp_since_ts) : '—'}</td><td className={Number(row.parcel_age_hours) >= 24 ? 'v2-risk-text' : ''}><strong>{fmt.decimal(row.parcel_age_hours)} jam</strong></td></tr>)}</tbody></table></div>{filtered.length > 20 && <button type="button" className="v2-show-more" onClick={() => setShowAll(!showAll)}>{showAll ? 'Tampilkan 20 pertama' : `Tampilkan semua ${fmt.number(filtered.length)} paket`}</button>}</> : <EmptyState title="Tidak ada paket yang cocok" message="Ubah filter atau pencarian untuk melihat paket lain." />}</section>;
}

function ComponentHealth({ detail, onSelect }) {
  const items = [
    ['Paket', detail.parcel_status, `${fmt.number(detail.parcel_at_dp)} di DP · ${fmt.number(detail.parcel_over_24h)} >24 jam`, 'parcels'],
    ['Pengiriman', detail.delivery_status, `${fmt.percent(detail.on_time_rate_pct)} tepat waktu · target ${fmt.percent(detail.delivery_sla_target_pct)}`, 'delivery'],
    ['Pendapatan', detail.revenue_status, `${fmt.percent(detail.revenue_achievement_pct)} target · gap ${fmt.percent(detail.revenue_gap_pct)}`, 'sellers'],
    ['Seller', detail.seller_status, `${fmt.number(detail.active_seller)} aktif · ${fmt.number(detail.critical_seller)} kritis`, 'sellers'],
  ];
  return <section className="v2-panel v2-health"><PanelHeading title="Kondisi tiap komponen" description="Status berasal dari analitik operasional." /><div>{items.map(([label, status, note, target]) => <button type="button" key={label} onClick={() => onSelect(target)}><span><strong>{label}</strong><small>{note}</small></span><StatusBadge status={status} /><ChevronRight size={17} /></button>)}</div></section>;
}

function OperationsContent({ detail, sections, pulse, days, setDays, setTab }) {
  const parcel = sections.parcels?.data || {};
  const delivery = sections.delivery?.summary || {};
  const preview = [...(sections.parcels?.issues || []).slice(0, 3), ...(sections.delivery?.issues || []).slice(0, 3)];
  return <><PriorityPanel rows={[detail]} onSelect={(item) => setTab(item.component === 'parcel' ? 'parcels' : item.component === 'delivery' ? 'delivery' : 'sellers')} /><div className="v2-detail-visuals"><PulseChart rows={pulse} days={days} onDaysChange={setDays} title="Arus paket Drop Point" /><AgeDistribution rows={detail} /></div><MetricStrip rows={detail} onClick={(key) => setTab(key.startsWith('parcel') ? 'parcels' : key === 'on_time_rate_pct' ? 'delivery' : 'sellers')} /><div className="v2-detail-split"><section className="v2-panel"><PanelHeading title="Ringkasan hari ini" description="Mengikuti tanggal simulasi pada data operasional." /><div className="v2-quick-grid"><QuickNumber label="Paket masuk" value={fmt.number(parcel.parcel_in_today)} note="Hari berjalan" /><QuickNumber label="Paket keluar" value={fmt.number(parcel.parcel_out_today)} note="Hari berjalan" /><QuickNumber label="Pengiriman berjalan" value={fmt.number(delivery.in_transit_delivery)} note="Bulan berjalan" /><QuickNumber label="Seller perlu perhatian" value={fmt.number(Number(detail.watch_seller || 0) + Number(detail.critical_seller || 0))} note="Waspada + kritis" /></div></section><ComponentHealth detail={detail} onSelect={setTab} /></div><section className="v2-panel v2-preview"><PanelHeading title="Cuplikan isu operasional" description="Buka halaman Paket atau Pengiriman untuk daftar lengkap." />{preview.length ? preview.map((row) => <div className="v2-preview-row" key={`${row.shipment_id}-${row.issue_type}`}><span className="v2-preview-dot" /><div><strong>{row.invoice_id || row.shipment_id}</strong><small>{row.parcel_issue_reason || row.delivery_issue_reason || row.issue_type}</small></div><span>{fmt.decimal(row.issue_hours)} jam</span></div>) : <EmptyState title="Tidak ada isu aktif" message="Daftar isu akan muncul saat ada paket atau pengiriman yang perlu ditangani." />}</section></>;
}

function ParcelsContent({ detail, sections, queue }) {
  const data = sections.parcels || {};
  const p = data.data || {};
  return <><div className="v2-section-intro"><h2>Arus dan usia paket</h2><p>Awasi paket yang sedang berada di DP, termasuk asal dan tujuan antar-DP.</p></div><div className="v2-detail-visuals"><section className="v2-panel"><PanelHeading title="Arus paket" description="Paket masuk dan keluar pada periode berjalan." /><div className="v2-quick-grid"><QuickNumber label="Masuk hari ini" value={fmt.number(p.parcel_in_today)} /><QuickNumber label="Keluar hari ini" value={fmt.number(p.parcel_out_today)} /><QuickNumber label="Masuk MTD" value={fmt.number(p.parcel_in_mtd)} /><QuickNumber label="Keluar MTD" value={fmt.number(p.parcel_out_mtd)} /></div><ProgressMeter value={p.parcel_out_pct} label="Rasio keluar terhadap masuk MTD" /></section><AgeDistribution rows={detail} /></div><ParcelQueue rows={queue.data || []} count={queue.count || 0} /><IssueTable issues={data.issues} type="parcels" /></>;
}

function DeliveryContent({ sections }) {
  const data = sections.delivery || {};
  const d = data.summary || {};
  return <><div className="v2-section-intro"><h2>Pengiriman dan SLA</h2><p>Kinerja last-mile dihitung pada Drop Point tujuan.</p></div><div className="v2-delivery-grid"><section className="v2-panel"><PanelHeading title="Ketepatan pengiriman" description="Pengiriman selesai pada bulan berjalan." /><div className="v2-large-percent">{fmt.percent(d.on_time_rate_pct)}</div><ProgressMeter value={d.on_time_rate_pct} target={d.delivery_sla_target_pct} label="SLA saat ini" tone={Number(d.on_time_rate_pct) >= Number(d.delivery_sla_target_pct) ? 'green' : 'red'} /><div className="v2-quick-grid"><QuickNumber label="Tepat waktu" value={fmt.number(d.on_time_delivery)} /><QuickNumber label="Terlambat" value={fmt.number(d.late_delivery)} /></div></section><section className="v2-panel"><PanelHeading title="Status pengiriman" description="Jumlah shipment bulan berjalan." /><div className="v2-quick-grid"><QuickNumber label="Total" value={fmt.number(d.total_shipment)} /><QuickNumber label="Selesai" value={fmt.number(d.completed_delivery)} /><QuickNumber label="Dalam perjalanan" value={fmt.number(d.in_transit_delivery)} /><QuickNumber label="Overdue aktif" value={fmt.number(d.overdue_delivery)} /><QuickNumber label="Gagal" value={fmt.number(d.failed_delivery)} /><QuickNumber label="Retur" value={fmt.number(d.returned_delivery)} /></div></section></div><IssueTable issues={data.issues} type="delivery" /></>;
}

function SellersContent({ detail, sections }) {
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('ALL');
  const sellers = sections.sellers?.data || [];
  const filtered = sellers.filter((row) => (status === 'ALL' || row.attention_status === status) && `${row.seller_name} ${row.seller_pic_name} ${row.city_area}`.toLowerCase().includes(query.toLowerCase()));
  return <><div className="v2-section-intro"><h2>Seller dan pendapatan</h2><p>Pendapatan adalah biaya layanan pengiriman, bukan nilai barang atau COD.</p></div><div className="v2-delivery-grid"><section className="v2-panel"><PanelHeading title="Capaian pendapatan" description="Bulan berjalan." /><div className="v2-large-money">{fmt.money(detail.revenue)}</div><ProgressMeter value={detail.revenue_achievement_pct} target={detail.expected_achievement_pct} label="Capaian / ekspektasi periode" /><div className="v2-quick-grid"><QuickNumber label="Target bulanan" value={fmt.money(detail.revenue_target)} /><QuickNumber label="Gap ke ekspektasi" value={fmt.percent(detail.revenue_gap_pct)} /></div></section><section className="v2-panel"><PanelHeading title="Kesehatan seller" description="Status dari pemantauan aktivitas transaksi." /><div className="v2-quick-grid"><QuickNumber label="Aktif" value={fmt.number(detail.active_seller)} /><QuickNumber label="Normal" value={fmt.number(detail.normal_seller)} /><QuickNumber label="Waspada" value={fmt.number(detail.watch_seller)} /><QuickNumber label="Kritis" value={fmt.number(detail.critical_seller)} /></div><ProgressMeter value={detail.active_seller_achievement_pct} label="Seller aktif / target" /></section></div><section className="v2-panel v2-data-panel"><PanelHeading title="Daftar seller" description={`${fmt.number(sellers.length)} seller dipantau`} action={<div className="v2-table-controls"><label className="v2-search"><Search size={16} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Cari seller atau PIC" aria-label="Cari seller" /></label><select value={status} onChange={(event) => setStatus(event.target.value)} aria-label="Filter status seller"><option value="ALL">Semua status</option><option value="CRITICAL">Kritis</option><option value="WATCH">Waspada</option><option value="NORMAL">Normal</option></select></div>} />{filtered.length ? <div className="v2-table-scroll"><table className="v2-data-table"><thead><tr><th>Seller</th><th>Area / PIC</th><th>Transaksi MTD</th><th>Pendapatan MTD</th><th>Aktivitas</th><th>Perhatian</th></tr></thead><tbody>{filtered.map((row) => <tr key={row.seller_id}><td><strong>{row.seller_name}</strong><small>{row.seller_code}</small></td><td>{row.city_area || '—'}<small>{row.seller_pic_name || '—'}</small></td><td>{fmt.number(row.current_month_transaction)}</td><td>{fmt.money(row.current_month_revenue)}</td><td>{row.activity_status || '—'}</td><td><StatusBadge status={row.attention_status} /></td></tr>)}</tbody></table></div> : <EmptyState title="Seller tidak ditemukan" message="Ubah pencarian atau status." />}</section></>;
}

function SellerPicsContent({ sections }) {
  const rows = sections['seller-pics']?.data || [];
  return <><div className="v2-section-intro"><h2>PIC Seller</h2><p>Setiap PIC dinilai pada pendapatan dan cakupan seller aktif.</p></div><section className="v2-panel v2-data-panel"><PanelHeading title="Performa PIC Seller" description={`${fmt.number(rows.length)} anggota tim seller`} />{rows.length ? <div className="v2-table-scroll"><table className="v2-data-table"><thead><tr><th>PIC</th><th>Status</th><th>Pendapatan</th><th>Target</th><th>Capaian</th><th>Seller aktif / target</th></tr></thead><tbody>{rows.map((row) => <tr key={row.staff_id}><td><strong>{row.staff_name}</strong></td><td><StatusBadge status={row.pic_status} /></td><td>{fmt.money(row.revenue)}</td><td>{fmt.money(row.revenue_target)}</td><td><div className="v2-sla-cell"><span>{fmt.percent(row.revenue_achievement_pct)}</span><div><span style={{ width: `${Math.max(0, Math.min(100, Number(row.revenue_achievement_pct || 0)))}%` }} /></div></div></td><td>{fmt.number(row.active_seller)} / {fmt.number(row.active_seller_target)}</td></tr>)}</tbody></table></div> : <EmptyState title="Belum ada PIC Seller" message="Data tim seller belum tersedia untuk DP ini." />}</section></>;
}

function TeamContent({ detail, sections }) {
  const team = sections.team?.data || [];
  const responsibility = sections.responsibility?.data || [];
  return <><div className="v2-section-intro"><h2>Tim dan tanggung jawab</h2><p>Manager DP memimpin eskalasi; setiap komponen memiliki unit operasional yang bertanggung jawab.</p></div><div className="v2-delivery-grid"><section className="v2-panel"><PanelHeading title="Struktur tim" description={`${fmt.number(team.length)} anggota tercatat`} />{team.length ? <div className="v2-team-list">{team.map((row) => <div key={row.staff_id}><span className="v2-avatar">{row.staff_name?.slice(0, 1) || '?'}</span><span><strong>{row.staff_name}</strong><small>{row.unit_name || row.unit_code} · {row.role_code}</small></span></div>)}</div> : <EmptyState title="Tim belum tersedia" />}</section><section className="v2-panel"><PanelHeading title="Peta penanggung jawab" description="Komponen berstatus waspada atau kritis." />{responsibility.length ? <div className="v2-responsibility-list">{responsibility.map((row) => <div key={row.component}><span><strong>{row.component}</strong><small>{row.responsible_unit_name || 'Unit belum ditetapkan'} · {row.responsible_staff_name || 'PIC belum ditetapkan'}</small></span><StatusBadge status={row.status} /></div>)}</div> : <EmptyState title="Belum ada eskalasi aktif" message={`Manager ${detail.manager_name || 'DP'} tetap memantau seluruh komponen.`} />}</section></div></>;
}

export default function DetailPage({ id, token, onBack, onUnauthorized, isRegional = true }) {
  const [tab, setTab] = useState('operations');
  const [detail, setDetail] = useState(null);
  const [sections, setSections] = useState({});
  const [queue, setQueue] = useState({ data: [], count: 0 });
  const [pulse, setPulse] = useState([]);
  const [days, setDays] = useState(7);
  const [loading, setLoading] = useState(true);
  const [sectionLoading, setSectionLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!id) return;
    const controller = new AbortController();
    setTab('operations'); setDetail(null); setSections({}); setQueue({ data: [], count: 0 });
    setLoading(true); setSectionLoading(true); setError('');
    api.detail(token, id, controller.signal).then(setDetail).catch((failure) => {
      if (failure.name === 'AbortError') return;
      if (failure.status === 401) onUnauthorized(); else setError(failure.message);
    }).finally(() => { if (!controller.signal.aborted) setLoading(false); });
    Promise.allSettled([...sectionsToLoad.map((section) => api.section(token, id, section, controller.signal)), api.parcelQueue(token, id, controller.signal)]).then((results) => {
      if (controller.signal.aborted) return;
      const loaded = {};
      sectionsToLoad.forEach((section, index) => { if (results[index].status === 'fulfilled') loaded[section] = results[index].value; });
      setSections(loaded);
      const queueResult = results.at(-1);
      if (queueResult.status === 'fulfilled') setQueue(queueResult.value);
      if (results.some((result) => result.status === 'rejected' && result.reason?.status === 401)) onUnauthorized();
      setSectionLoading(false);
    });
    return () => controller.abort();
  }, [id, token, onUnauthorized]);

  useEffect(() => {
    if (!id) return;
    const controller = new AbortController();
    api.dpPulse(token, id, days, controller.signal).then((result) => setPulse(result.data || [])).catch((failure) => {
      if (failure.name !== 'AbortError' && failure.status === 401) onUnauthorized();
    });
    return () => controller.abort();
  }, [id, token, days, onUnauthorized]);

  const selectedLabel = useMemo(() => tabs.find(([key]) => key === tab)?.[1], [tab]);
  if (!id) return <div className="page-content"><EmptyState title="Belum ada Drop Point" message="Akun ini belum memiliki akses DP aktif." /></div>;
  return <div className="page-content v2-page v2-detail-page">{isRegional && <button type="button" className="v2-back" onClick={onBack}><ArrowLeft size={16} /> Kembali ke Drop Points</button>}{loading && !detail ? <LoadingState /> : error && !detail ? <ErrorState message={error} /> : detail && <><div className="v2-page-intro v2-detail-intro"><div><span className="v2-eyebrow">DROP POINT / {detail.drop_point_id}</span><div className="v2-detail-title"><h1>{detail.drop_point_name}</h1><StatusBadge status={detail.overall_status} /></div><p>{detail.area || detail.region} · Manager {detail.manager_name || 'belum ditetapkan'}</p></div><div className="v2-asof"><CalendarDays size={18} /><span><strong>{fmt.date(detail.as_of_date)}</strong><small>Waktu data simulasi</small></span></div></div>
    <nav className="v2-detail-tabs" aria-label="Halaman Drop Point">{tabs.map(([key, label]) => <button key={key} type="button" className={tab === key ? 'is-active' : ''} aria-current={tab === key ? 'page' : undefined} onClick={() => { setTab(key); window.scrollTo({ top: 0, behavior: 'smooth' }); }}>{label}</button>)}</nav><div className="v2-tab-heading"><span>{selectedLabel}</span><strong>{detail.drop_point_name}</strong></div>
    {sectionLoading && <p className="v2-data-loading"><Clock3 size={15} /> Memuat rincian operasional…</p>}
    {tab === 'operations' && <OperationsContent detail={detail} sections={sections} pulse={pulse} days={days} setDays={setDays} setTab={setTab} />}
    {tab === 'parcels' && <ParcelsContent detail={detail} sections={sections} queue={queue} />}
    {tab === 'delivery' && <DeliveryContent sections={sections} />}
    {tab === 'sellers' && <SellersContent detail={detail} sections={sections} />}
    {tab === 'seller-pics' && <SellerPicsContent sections={sections} />}
    {tab === 'team' && <TeamContent detail={detail} sections={sections} />}
    <div className="v2-detail-footer"><span>Data akses terbatas untuk akun Anda.</span><button type="button" onClick={() => setTab('operations')}>Kembali ke ringkasan <ArrowUpRight size={15} /></button></div>
  </>}</div>;
}
