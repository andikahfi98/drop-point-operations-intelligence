import { useState } from 'react';
import { ArrowRight, LockKeyhole } from 'lucide-react';
import { Logo } from '../components/Ui';

export default function PasswordPage({ onChange, onLogout }) {
  const [current, setCurrent] = useState('');
  const [next, setNext] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState('');
  const [pending, setPending] = useState(false);

  async function submit(event) {
    event.preventDefault();
    if (next !== confirm) { setError('Konfirmasi password belum sama.'); return; }
    if (new TextEncoder().encode(next).length > 72) { setError('Password maksimal 72 byte UTF-8.'); return; }
    setPending(true); setError('');
    try { await onChange(current, next); }
    catch (failure) { setError(failure.status === 401 ? 'Password saat ini tidak sesuai.' : failure.message); }
    finally { setPending(false); }
  }

  return <main className="password-screen"><div className="password-card"><Logo /><div className="password-symbol"><LockKeyhole size={26} /></div><h1>Amankan akun Anda</h1><p>Akun demo memerlukan password baru sebelum data dashboard dapat dibuka. Setelah disimpan, masuk kembali dengan password baru.</p>{error && <div className="form-error" role="alert">{error}</div>}
    <form onSubmit={submit}><label htmlFor="current">Password saat ini</label><input id="current" type="password" autoComplete="current-password" required value={current} onChange={(event) => setCurrent(event.target.value)} /><label htmlFor="next">Password baru</label><input id="next" type="password" autoComplete="new-password" minLength={12} required value={next} onChange={(event) => setNext(event.target.value)} /><span className="field-hint">Minimal 12 karakter.</span><label htmlFor="confirm">Ulangi password baru</label><input id="confirm" type="password" autoComplete="new-password" required value={confirm} onChange={(event) => setConfirm(event.target.value)} /><button className="primary-button" type="submit" disabled={pending}>Simpan password baru <ArrowRight size={17} /></button></form><button type="button" className="text-button password-back" onClick={onLogout}>Kembali ke login</button></div></main>;
}
