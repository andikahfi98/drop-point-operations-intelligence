import { useState } from 'react';
import { Eye, EyeOff, LockKeyhole, Mail, MapPin, Package, Truck } from 'lucide-react';
import { Logo } from '../components/Ui';

function RouteArt() {
  return <div className="route-art" aria-hidden="true"><svg viewBox="0 0 760 640" preserveAspectRatio="xMidYMid slice"><path className="route-grid" d="M-80 478 220 330 534 482 840 314M-92 560 224 408 526 560 850 392M-60 338 250 188 560 338 842 200M84 126 426 292M428 48 734 202" /><path className="route-line" d="M62 474 C172 426 206 574 310 512 S430 300 510 354 S644 444 732 322" /><circle cx="62" cy="474" r="9" /><circle cx="310" cy="512" r="9" /><circle cx="510" cy="354" r="9" /><circle cx="732" cy="322" r="9" /></svg><span className="route-icon route-icon-one"><Package size={37} strokeWidth={1.25} /></span><span className="route-icon route-icon-two"><Truck size={47} strokeWidth={1.2} /></span><span className="route-icon route-icon-three"><MapPin size={32} strokeWidth={1.5} /></span></div>;
}

export default function LoginPage({ onLogin, message }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState('');

  async function submit(event) {
    event.preventDefault();
    setError('');
    setPending(true);
    try { await onLogin(email, password); }
    catch (failure) { setError(failure.status === 401 ? 'Email atau password tidak sesuai.' : failure.message); }
    finally { setPending(false); }
  }

  return <main className="login-layout">
    <section className="login-brand"><Logo light /><div className="login-brand-message"><h1>Pantau setiap<br />drop point<br />dengan jelas.</h1><p>Informasi operasional yang tepat untuk keputusan setiap hari.</p></div><RouteArt /></section>
    <section className="login-form-side"><div className="login-form-wrap"><Logo /><h2>Masuk ke dashboard</h2><p className="login-intro">Akses data operasional drop point Anda dengan aman.</p>
      {message && <div className="notice" role="status">{message}</div>}
      {error && <div className="form-error" role="alert">{error}</div>}
      <form onSubmit={submit}><label htmlFor="email">Email</label><div className="input-shell"><Mail size={19} /><input id="email" type="email" autoComplete="username" placeholder="Masukkan email Anda" value={email} onChange={(event) => setEmail(event.target.value)} required /></div>
        <label htmlFor="password">Password</label><div className="input-shell"><LockKeyhole size={19} /><input id="password" type={showPassword ? 'text' : 'password'} autoComplete="current-password" placeholder="Masukkan password Anda" value={password} onChange={(event) => setPassword(event.target.value)} required /><button type="button" className="reveal-button" onClick={() => setShowPassword(!showPassword)} aria-label={showPassword ? 'Sembunyikan password' : 'Tampilkan password'}>{showPassword ? <EyeOff size={20} /> : <Eye size={20} />}</button></div>
        <button className="primary-button login-submit" type="submit" disabled={pending}>{pending ? 'Memproses…' : 'Masuk'}</button>
      </form></div><p className="login-footnote">Dashboard operasional internal · Pengembangan lokal</p></section>
  </main>;
}
