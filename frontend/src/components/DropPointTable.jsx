import { useMemo, useState } from 'react';
import { ArrowDown, ArrowUp, ChevronRight } from 'lucide-react';
import { fmt } from '../format';
import { EmptyState, SearchFilters, StatusBadge } from './Ui';

const fields = [
  ['drop_point_name', 'Drop Point'], ['region', 'Region'], ['parcel_at_dp', 'Paket di DP'],
  ['parcel_over_24h', 'Paket > 24 jam'], ['on_time_rate_pct', 'SLA'],
  ['active_seller', 'Seller aktif'], ['overall_status', 'Status'],
];

export default function DropPointTable({ rows, onOpen, selectedId, title = 'Daftar Drop Point', description, compact = false, statusFilter, onStatusFilterChange }) {
  const [query, setQuery] = useState('');
  const [region, setRegion] = useState('ALL');
  const [status, setStatus] = useState('ALL');
  const [sort, setSort] = useState({ key: 'parcel_at_dp', direction: 'desc' });
  const regions = useMemo(() => [...new Set(rows.map((row) => row.region).filter(Boolean))].sort(), [rows]);
  const activeStatus = statusFilter ?? status;
  const filtered = useMemo(() => rows.filter((row) =>
    (region === 'ALL' || row.region === region) &&
    (activeStatus === 'ALL' || row.overall_status === activeStatus) &&
    `${row.drop_point_name} ${row.drop_point_id}`.toLocaleLowerCase('id-ID').includes(query.toLocaleLowerCase('id-ID'))
  ).sort((a, b) => {
    const left = a[sort.key] ?? '';
    const right = b[sort.key] ?? '';
    const comparison = typeof left === 'number' || (!Number.isNaN(Number(left)) && left !== '')
      ? Number(left) - Number(right)
      : String(left).localeCompare(String(right), 'id-ID');
    return sort.direction === 'asc' ? comparison : -comparison;
  }), [rows, region, activeStatus, query, sort]);
  const toggleSort = (key) => setSort((current) => ({ key, direction: current.key === key && current.direction === 'desc' ? 'asc' : 'desc' }));

  return <section className={`table-panel ${compact ? 'table-panel-compact' : ''}`} aria-label={title}>
    <div className="table-panel-heading"><div><h2>{title}</h2>{description && <p>{description}</p>}</div></div>
    <SearchFilters query={query} onQuery={setQuery} region={region} onRegion={setRegion} status={activeStatus} onStatus={onStatusFilterChange || setStatus} regions={regions} count={filtered.length} />
    {filtered.length ? <div className="table-scroll"><table className="data-table dp-table"><thead><tr>{fields.map(([key, label]) => <th key={key} scope="col" aria-sort={sort.key === key ? (sort.direction === 'asc' ? 'ascending' : 'descending') : 'none'}><button type="button" className="sort-button" onClick={() => toggleSort(key)}>{label}{sort.key === key ? (sort.direction === 'asc' ? <ArrowUp size={13} /> : <ArrowDown size={13} />) : null}</button></th>)}<th scope="col"><span className="sr-only">Buka detail</span></th></tr></thead>
      <tbody>{filtered.map((row) => <tr key={row.drop_point_id} className={selectedId === row.drop_point_id ? 'row-selected' : ''}>
        <td data-label="Drop Point"><button type="button" className="row-link" onClick={() => onOpen(row.drop_point_id)}><span className="row-id-mark" />{row.drop_point_name}</button></td>
        <td data-label="Region">{row.region || '—'}</td><td data-label="Paket di DP" className="number-cell">{fmt.number(row.parcel_at_dp)}</td>
        <td data-label="Paket > 24 jam" className={`number-cell ${Number(row.parcel_over_24h) > 0 ? 'emphasis-red' : ''}`}>{fmt.number(row.parcel_over_24h)}</td>
        <td data-label="SLA" className="number-cell">{fmt.percent(row.on_time_rate_pct)}</td><td data-label="Seller aktif" className="number-cell">{fmt.number(row.active_seller)}</td>
        <td data-label="Status"><StatusBadge status={row.overall_status} /></td><td><button className="icon-button row-open" type="button" onClick={() => onOpen(row.drop_point_id)} aria-label={`Lihat detail ${row.drop_point_name}`}><ChevronRight size={18} /></button></td>
      </tr>)}</tbody></table></div> : <EmptyState title="Drop Point tidak ditemukan" message="Coba ubah kata pencarian atau filter." />}
  </section>;
}
