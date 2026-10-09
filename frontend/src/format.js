const number = new Intl.NumberFormat('id-ID');
const decimal = new Intl.NumberFormat('id-ID', { maximumFractionDigits: 1 });
const currency = new Intl.NumberFormat('id-ID', { style: 'currency', currency: 'IDR', maximumFractionDigits: 0 });

export const fmt = {
  number: (value) => value == null ? '—' : number.format(Number(value)),
  decimal: (value) => value == null ? '—' : decimal.format(Number(value)),
  percent: (value) => value == null ? '—' : `${decimal.format(Number(value))}%`,
  money: (value) => value == null ? '—' : currency.format(Number(value)),
  date: (value) => {
    if (!value) return '—';
    const date = new Date(`${String(value).slice(0, 10)}T00:00:00`);
    return Number.isNaN(date.getTime()) ? String(value) : new Intl.DateTimeFormat('id-ID', { day: 'numeric', month: 'long', year: 'numeric' }).format(date);
  },
};

export const statusLabel = { NORMAL: 'Normal', WATCH: 'Waspada', CRITICAL: 'Kritis', UNKNOWN: 'Belum tersedia' };
export const statusClass = (status) => ['NORMAL', 'WATCH', 'CRITICAL'].includes(status) ? status.toLowerCase() : 'unknown';

export function sum(rows, key) {
  return rows.reduce((total, row) => total + (Number(row[key]) || 0), 0);
}

export function csvDownload(filename, rows, columns) {
  const escape = (value) => `"${String(value ?? '').replaceAll('"', '""')}"`;
  const csv = '\uFEFF' + [columns.map(([label]) => escape(label)).join(','), ...rows.map((row) => columns.map(([, key]) => escape(row[key])).join(','))].join('\r\n');
  const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}
