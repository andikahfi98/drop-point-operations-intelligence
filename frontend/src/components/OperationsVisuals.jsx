import { useMemo, useState } from 'react';
import { ArrowUpRight, Clock3, Package, Search, Target, Wallet } from 'lucide-react';
import { fmt, sum } from '../format';
import { EmptyState, StatusBadge } from './Ui';

const aging = [
  ['parcel_under_6h', '0–6 jam', 'fresh'],
  ['parcel_6_12h', '6–12 jam', 'mid'],
  ['parcel_12_24h', '12–24 jam', 'late'],
  ['parcel_over_24h', '>24 jam', 'risk'],
];

export function PanelHeading({ title, description, action }) {
  return <div className="v2-panel-heading"><div><h2>{title}</h2>{description && <p>{description}</p>}</div>{action}</div>;
}

export function PulseChart({ rows, days, onDaysChange, title = 'Pergerakan paket', description = 'Paket masuk dan keluar per hari berdasarkan waktu simulasi.' }) {
  const series = useMemo(() => {
    const byDay = new Map();
    rows.forEach((row) => {
      const day = String(row.business_date).slice(0, 10);
      const point = byDay.get(day) || { day, parcel_in: 0, parcel_out: 0, delivered: 0, revenue: 0 };
      point.parcel_in += Number(row.parcel_in || 0);
      point.parcel_out += Number(row.parcel_out || 0);
      point.delivered += Number(row.delivered || 0);
      point.revenue += Number(row.revenue || 0);
      byDay.set(day, point);
    });
    return [...byDay.values()].sort((a, b) => a.day.localeCompare(b.day));
  }, [rows]);
  const [selectedDay, setSelectedDay] = useState(null);
  const activeIndex = selectedDay ? Math.max(0, series.findIndex((item) => item.day === selectedDay)) : Math.max(0, series.length - 1);
  const selected = series[activeIndex] || series.at(-1);
  const width = 680; const height = 242;
  const left = 36; const right = 16; const top = 15; const bottom = 34;
  const plotWidth = width - left - right; const plotHeight = height - top - bottom;
  const max = Math.max(1, ...series.flatMap((row) => [row.parcel_in, row.parcel_out]));
  const ceiling = Math.ceil(max / 5) * 5 || 5;
  const x = (index) => left + (series.length === 1 ? plotWidth / 2 : index * plotWidth / (series.length - 1));
  const y = (value) => top + plotHeight - Number(value || 0) / ceiling * plotHeight;
  const path = (key) => series.map((point, index) => `${index ? 'L' : 'M'} ${x(index)} ${y(point[key])}`).join(' ');
  const area = series.length ? `${path('parcel_in')} L ${x(series.length - 1)} ${top + plotHeight} L ${x(0)} ${top + plotHeight} Z` : '';
  const control = <div className="v2-segmented" aria-label="Rentang waktu">{[7, 14].map((value) => <button key={value} type="button" aria-pressed={days === value} className={days === value ? 'is-active' : ''} onClick={() => onDaysChange(value)}>{value} hari</button>)}</div>;
  return <section className="v2-panel v2-trend-panel" aria-label={title}>
    <PanelHeading title={title} description={description} action={control} />
    {!series.length ? <EmptyState title="Belum ada riwayat" message="Grafik tersedia setelah arus paket tercatat." /> : <div className="v2-trend-layout"><div className="v2-chart-wrap"><div className="v2-chart-legend"><span><i className="v2-legend-in" /> Masuk</span><span><i className="v2-legend-out" /> Keluar</span></div><svg viewBox={`0 0 ${width} ${height}`} className="v2-line-chart" role="img" aria-label={`Grafik paket masuk dan keluar selama ${days} hari`}>
      <defs><linearGradient id="pulse-fill" x1="0" x2="0" y1="0" y2="1"><stop offset="0%" stopColor="#e31d2a" stopOpacity=".17" /><stop offset="100%" stopColor="#e31d2a" stopOpacity="0" /></linearGradient></defs>
      {[0, .25, .5, .75, 1].map((ratio) => <g key={ratio}><line x1={left} x2={width - right} y1={top + plotHeight * ratio} y2={top + plotHeight * ratio} stroke="#e7eaf0" strokeDasharray={ratio === 1 ? undefined : '3 5'} /><text x="0" y={top + plotHeight * ratio + 4} fill="#687386" fontSize="11">{fmt.number(Math.round(ceiling * (1 - ratio)))}</text></g>)}
      <path d={area} fill="url(#pulse-fill)" /><path d={path('parcel_out')} fill="none" stroke="#566273" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" /><path d={path('parcel_in')} fill="none" stroke="#d71920" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round" />
      {series.map((point, index) => <g key={point.day} tabIndex="0" role="button" aria-label={`${fmt.date(point.day)}: ${fmt.number(point.parcel_in)} masuk, ${fmt.number(point.parcel_out)} keluar`} onFocus={() => setSelectedDay(point.day)} onMouseEnter={() => setSelectedDay(point.day)} onClick={() => setSelectedDay(point.day)} className="v2-chart-point"><circle cx={x(index)} cy={y(point.parcel_in)} r="11" fill="transparent" /><circle cx={x(index)} cy={y(point.parcel_in)} r={selected?.day === point.day ? 5 : 3.5} fill="#d71920" stroke="white" strokeWidth="2" /><circle cx={x(index)} cy={y(point.parcel_out)} r={selected?.day === point.day ? 4.5 : 3} fill="#566273" stroke="white" strokeWidth="2" /></g>)}
      {series.map((point, index) => (days === 14 && index % 2 && index !== series.length - 1) ? null : <text key={point.day} x={x(index)} y={height - 8} textAnchor="middle" fill="#687386" fontSize="11">{new Intl.DateTimeFormat('id-ID', { day: 'numeric', month: 'short' }).format(new Date(`${point.day}T00:00:00`))}</text>)}
    </svg></div><div className="v2-chart-inspector"><span>DATA TERPILIH</span><strong>{fmt.date(selected.day)}</strong><div><i className="v2-legend-in" />Paket masuk<b>{fmt.number(selected.parcel_in)}</b></div><div><i className="v2-legend-out" />Paket keluar<b>{fmt.number(selected.parcel_out)}</b></div><hr /><small>Pengiriman selesai</small><b>{fmt.number(selected.delivered)}</b></div></div>}
  </section>;
}

export function AgeDistribution({ rows, compact = false }) {
  const counts = aging.map(([key, label, tone]) => ({ key, label, tone, value: Array.isArray(rows) ? sum(rows, key) : Number(rows?.[key] || 0) }));
  const total = counts.reduce((value, item) => value + item.value, 0);
  return <section className={`v2-panel v2-aging ${compact ? 'v2-aging-compact' : ''}`}><PanelHeading title="Usia paket di DP" description="Paket yang masih berada secara fisik di Drop Point." /><div className="v2-age-total"><strong>{fmt.number(total)}</strong><span>paket saat ini</span></div><div className="v2-age-stack" role="img" aria-label={counts.map((item) => `${item.label}: ${fmt.number(item.value)}`).join(', ')}>{counts.map((item) => <span key={item.key} className={`age-${item.tone}`} style={{ width: `${total ? item.value / total * 100 : 0}%` }} />)}</div><div className="v2-age-list">{counts.map((item) => <div key={item.key}><span className={`v2-age-dot age-${item.tone}`} /><span>{item.label}</span><strong>{fmt.number(item.value)}</strong><small>{total ? fmt.percent(item.value / total * 100) : '0%'}</small></div>)}</div></section>;
}

const metrics = [
  { key: 'parcel_at_dp', label: 'Paket di DP', icon: Package, note: (row) => `${fmt.number(row.parcel_in_mtd)} masuk MTD` },
  { key: 'parcel_over_24h', label: 'Paket >24 jam', icon: Clock3, note: (row) => `${fmt.decimal(row.oldest_parcel_hours)} jam tertua` },
  { key: 'on_time_rate_pct', label: 'Ketepatan SLA', icon: Target, format: fmt.percent, note: (row) => `Target ${fmt.percent(row.delivery_sla_target_pct)}` },
  { key: 'revenue', label: 'Pendapatan MTD', icon: Wallet, format: fmt.money, note: (row) => `${fmt.percent(row.revenue_achievement_pct)} dari target` },
];

export function MetricStrip({ rows, onClick }) {
  const aggregate = Array.isArray(rows) ? {
    parcel_at_dp: sum(rows, 'parcel_at_dp'), parcel_in_mtd: sum(rows, 'parcel_in_mtd'),
    parcel_over_24h: sum(rows, 'parcel_over_24h'), oldest_parcel_hours: Math.max(0, ...rows.map((row) => Number(row.oldest_parcel_hours || 0))),
    on_time_rate_pct: sum(rows, 'completed_delivery') ? sum(rows, 'on_time_delivery') / sum(rows, 'completed_delivery') * 100 : null,
    delivery_sla_target_pct: rows.length ? Number(rows[0].delivery_sla_target_pct) : null,
    revenue: sum(rows, 'revenue'), revenue_target: sum(rows, 'revenue_target'),
    revenue_achievement_pct: sum(rows, 'revenue_target') ? sum(rows, 'revenue') / sum(rows, 'revenue_target') * 100 : null,
  } : rows;
  return <div className="v2-metric-strip">{metrics.map(({ key, label, icon: Icon, note, format }, index) => <button key={key} type="button" className="v2-metric" onClick={() => onClick?.(key)} disabled={!onClick}><span className="v2-metric-icon"><Icon size={20} /></span><span className="v2-metric-label">{label}</span><strong>{(format || fmt.number)(aggregate?.[key])}</strong><small>{note(aggregate || {})}</small>{onClick && <ArrowUpRight className="v2-metric-arrow" size={17} />}</button>)}</div>;
}

const componentLabels = { parcel: 'Paket', delivery: 'Pengiriman', revenue: 'Pendapatan', seller: 'Seller' };
export function derivePriorities(rows) {
  const result = [];
  rows.forEach((row) => {
    const candidates = [
      ['parcel', row.parcel_status, `${fmt.number(row.parcel_over_24h)} paket >24 jam · tertua ${fmt.decimal(row.oldest_parcel_hours)} jam`],
      ['delivery', row.delivery_status, `SLA ${fmt.percent(row.on_time_rate_pct)} / target ${fmt.percent(row.delivery_sla_target_pct)} · ${fmt.number(row.overdue_delivery)} overdue`],
      ['revenue', row.revenue_status, `Capaian ${fmt.percent(row.revenue_achievement_pct)} / ekspektasi ${fmt.percent(row.expected_achievement_pct)}`],
      ['seller', row.seller_status, `${fmt.number(row.critical_seller)} kritis · ${fmt.number(row.watch_seller)} waspada`],
    ];
    candidates.forEach(([component, status, detail]) => {
      if (status === 'WATCH' || status === 'CRITICAL') result.push({ ...row, component, status, detail });
    });
  });
  return result.sort((a, b) => (a.status === 'CRITICAL' ? 0 : 1) - (b.status === 'CRITICAL' ? 0 : 1) || Number(b.parcel_over_24h || 0) - Number(a.parcel_over_24h || 0));
}

export function PriorityPanel({ rows, onSelect }) {
  const priorities = derivePriorities(rows).slice(0, 3);
  return <section className="v2-priority"><div className="v2-priority-heading"><div><span>FOKUS OPERASIONAL</span><h2>Perlu ditindaklanjuti</h2></div><strong>{priorities.length}</strong></div>{priorities.length ? <div className="v2-priority-list">{priorities.map((item, index) => <button key={`${item.drop_point_id}-${item.component}`} type="button" onClick={() => onSelect(item)}><span className="v2-priority-index">0{index + 1}</span><span><strong>{componentLabels[item.component]} · {item.drop_point_name}</strong><small>{item.detail}</small></span><ArrowUpRight size={17} /></button>)}</div> : <p className="v2-priority-empty">Belum ada komponen berstatus waspada atau kritis. Lanjutkan pemantauan rutin.</p>}</section>;
}

export function PerformanceTable({ rows, onOpen }) {
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('ALL');
  const [sort, setSort] = useState('risk');
  const filtered = useMemo(() => [...rows].filter((row) => (status === 'ALL' || row.overall_status === status) && `${row.drop_point_name} ${row.area}`.toLowerCase().includes(query.toLowerCase())).sort((a, b) => {
    if (sort === 'name') return a.drop_point_name.localeCompare(b.drop_point_name, 'id-ID');
    if (sort === 'sla') return Number(a.on_time_rate_pct || 0) - Number(b.on_time_rate_pct || 0);
    if (sort === 'parcel') return Number(b.parcel_at_dp || 0) - Number(a.parcel_at_dp || 0);
    const rank = { CRITICAL: 0, WATCH: 1, NORMAL: 2 };
    return (rank[a.overall_status] ?? 3) - (rank[b.overall_status] ?? 3) || Number(a.on_time_rate_pct || 0) - Number(b.on_time_rate_pct || 0);
  }), [rows, query, status, sort]);
  return <section className="v2-panel v2-performance"><PanelHeading title="Performa Drop Point" description="Klik baris untuk melihat paket, pengiriman, seller, dan penanggung jawab." action={<div className="v2-table-controls"><label className="v2-search"><Search size={16} /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Cari Drop Point" aria-label="Cari Drop Point" /></label><select value={status} onChange={(event) => setStatus(event.target.value)} aria-label="Filter status"><option value="ALL">Semua status</option><option value="CRITICAL">Kritis</option><option value="WATCH">Waspada</option><option value="NORMAL">Normal</option></select><select value={sort} onChange={(event) => setSort(event.target.value)} aria-label="Urutkan Drop Point"><option value="risk">Prioritas</option><option value="sla">SLA terendah</option><option value="parcel">Paket terbanyak</option><option value="name">Nama</option></select></div>} />
    {filtered.length ? <div className="v2-performance-scroll"><table><thead><tr><th>Drop Point</th><th>Status</th><th>Paket di DP</th><th>Usia paket</th><th>SLA / target</th><th>Pendapatan MTD</th><th aria-label="Buka detail" /></tr></thead><tbody>{filtered.map((row) => {
      const ageTotal = ['parcel_under_6h', 'parcel_6_12h', 'parcel_12_24h', 'parcel_over_24h'].reduce((n, key) => n + Number(row[key] || 0), 0);
      const ageParts = aging.map(([key, , tone]) => <span key={key} className={`age-${tone}`} style={{ width: `${ageTotal ? Number(row[key] || 0) / ageTotal * 100 : 0}%` }} />);
      const sla = Number(row.on_time_rate_pct || 0);
      return <tr key={row.drop_point_id} onClick={() => onOpen(row.drop_point_id)}><td><button type="button" onClick={(event) => { event.stopPropagation(); onOpen(row.drop_point_id); }}><strong>{row.drop_point_name}</strong><small>{row.area || row.region}</small></button></td><td><StatusBadge status={row.overall_status} /></td><td><strong>{fmt.number(row.parcel_at_dp)}</strong><small>{fmt.number(row.parcel_over_24h)} &gt;24 jam</small></td><td><div className="v2-mini-age" aria-label={`Distribusi usia paket ${row.drop_point_name}`}>{ageParts}</div></td><td><div className="v2-sla-cell"><span>{fmt.percent(row.on_time_rate_pct)} <small>/ {fmt.percent(row.delivery_sla_target_pct)}</small></span><div><span style={{ width: `${Math.min(100, sla)}%` }} /></div></div></td><td><strong>{fmt.money(row.revenue)}</strong><small>{fmt.percent(row.revenue_achievement_pct)} target</small></td><td><ArrowUpRight size={17} /></td></tr>;
    })}</tbody></table></div> : <EmptyState title="Drop Point tidak ditemukan" message="Ubah pencarian atau status untuk melihat hasil lain." />}</section>;
}
