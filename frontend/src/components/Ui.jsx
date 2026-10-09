import { ArrowUpRight, ChevronDown, Search } from 'lucide-react';
import { fmt, statusClass, statusLabel } from '../format';

export function Logo({ light = false }) {
  return <img className={`brand-logo ${light ? 'brand-logo-light' : ''}`} src="./jnt-express.svg" alt="J&T Express" />;
}

export function StatusBadge({ status }) {
  return <span className={`status status-${statusClass(status)}`}><span className="status-dot" />{statusLabel[status] || status || 'Belum tersedia'}</span>;
}

export function EmptyState({ title = 'Tidak ada data', message = 'Belum ada informasi untuk ditampilkan.' }) {
  return <div className="empty-state"><strong>{title}</strong><p>{message}</p></div>;
}

export function ErrorState({ message, onRetry }) {
  return <div className="error-state" role="alert"><strong>Data belum dapat dimuat</strong><p>{message}</p>{onRetry && <button className="text-button" onClick={onRetry}>Coba lagi <ArrowUpRight size={16} /></button>}</div>;
}

export function LoadingState({ label = 'Memuat data operasional…' }) {
  return <div className="loading-state" role="status"><span className="loading-spinner" />{label}</div>;
}

export function SearchFilters({ query, onQuery, region, onRegion, status, onStatus, regions, count }) {
  return <div className="filter-bar">
    <label className="search-field"><Search size={18} aria-hidden="true" /><span className="sr-only">Cari nama drop point</span><input type="search" value={query} onChange={(event) => onQuery(event.target.value)} placeholder="Cari nama drop point…" /></label>
    <span className="filter-count">{fmt.number(count)} DP</span>
    <label className="select-wrap"><span className="sr-only">Filter region</span><select value={region} onChange={(event) => onRegion(event.target.value)}><option value="ALL">Semua region</option>{regions.map((item) => <option key={item} value={item}>{item}</option>)}</select><ChevronDown size={16} aria-hidden="true" /></label>
    <label className="select-wrap"><span className="sr-only">Filter status</span><select value={status} onChange={(event) => onStatus(event.target.value)}><option value="ALL">Semua status</option><option value="CRITICAL">Kritis</option><option value="WATCH">Waspada</option><option value="NORMAL">Normal</option></select><ChevronDown size={16} aria-hidden="true" /></label>
  </div>;
}
