import { useCallback, useEffect, useState } from 'react';
import { BarChart3, CalendarDays, ChevronDown, ClipboardList, LogOut, MapPin, Menu, RefreshCw, X } from 'lucide-react';
import { api } from './api';
import { PerformanceTable } from './components/OperationsVisuals';
import { ErrorState, LoadingState, Logo } from './components/Ui';
import { fmt } from './format';
import DetailPage from './pages/DetailPage';
import LoginPage from './pages/LoginPage';
import OverviewPage from './pages/OverviewPage';
import PasswordPage from './pages/PasswordPage';
import ReportPage from './pages/ReportPage';

function navigationFor(user) {
  return user.role_code === 'REGIONAL_MANAGER' ? [
    ['overview', 'Overview', BarChart3], ['drop-points', 'Drop Points', MapPin],
    ['report', 'Laporan', ClipboardList],
  ] : [
    ['detail', 'DP Saya', MapPin], ['report', 'Laporan', ClipboardList],
  ];
}

function Shell({ user, view, onNavigate, onLogout, rows, refresh, refreshing, children }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const [userOpen, setUserOpen] = useState(false);
  const items = navigationFor(user);
  const activeView = view === 'detail' && user.role_code === 'REGIONAL_MANAGER' ? 'drop-points' : view;
  return <div className="workspace-shell"><a className="skip-link" href="#main-content">Lewati navigasi</a><header className="workspace-header"><div className="workspace-brand"><Logo /><span>OPERATIONS<br />INTELLIGENCE</span></div><nav className={`workspace-nav ${menuOpen ? 'workspace-nav-open' : ''}`} aria-label="Navigasi utama">{items.map(([key, label, Icon]) => <button key={key} type="button" className={activeView === key ? 'is-active' : ''} onClick={() => { onNavigate(key); setMenuOpen(false); }}><Icon size={17} /><span>{label}</span></button>)}</nav><div className="workspace-header-end"><span className="workspace-clock"><CalendarDays size={16} />{fmt.date(rows[0]?.as_of_date)} <small>simulasi</small></span><button className={`workspace-refresh ${refreshing ? 'is-refreshing' : ''}`} type="button" aria-label="Perbarui data" onClick={refresh} disabled={refreshing}><RefreshCw size={18} /></button><div className="workspace-user"><button type="button" aria-expanded={userOpen} onClick={() => setUserOpen(!userOpen)}><span className="workspace-avatar">{user.full_name?.split(' ').map((part) => part[0]).slice(0, 2).join('').toUpperCase() || 'JT'}</span><span><strong>{user.full_name}</strong><small>{user.role_code === 'REGIONAL_MANAGER' ? 'Regional Manager' : 'DP Manager'}</small></span><ChevronDown size={15} /></button>{userOpen && <div className="workspace-popover"><span>{user.email}</span><button type="button" onClick={onLogout}><LogOut size={16} /> Keluar</button></div>}</div><button type="button" className="workspace-menu" aria-label={menuOpen ? 'Tutup menu' : 'Buka menu'} onClick={() => setMenuOpen(!menuOpen)}>{menuOpen ? <X size={21} /> : <Menu size={21} />}</button></div></header><main id="main-content">{children}</main></div>;
}

export default function App() {
  const [session, setSession] = useState(null);
  const [loginMessage, setLoginMessage] = useState('');
  const [rows, setRows] = useState([]);
  const [view, setView] = useState('overview');
  const [selectedId, setSelectedId] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [refreshKey, setRefreshKey] = useState(0);

  const unauthorized = useCallback(() => { setSession(null); setRows([]); setLoginMessage('Sesi berakhir. Silakan masuk kembali.'); }, []);
  const login = async (email, password) => {
    const result = await api.login(email, password);
    try {
      const user = await api.me(result.access_token);
      setSession({ token: result.access_token, user });
      setLoginMessage('');
      const isDpManager = user.role_code === 'DP_MANAGER';
      setSelectedId(isDpManager ? user.drop_points?.[0]?.drop_point_id || null : null);
      setView(isDpManager ? 'detail' : 'overview');
    } catch (failure) {
      await api.logout(result.access_token).catch(() => {});
      throw failure;
    }
  };
  const logout = async () => {
    const token = session?.token;
    setSession(null); setRows([]); setView('overview'); setSelectedId(null);
    if (token) await api.logout(token).catch(() => {});
  };
  const changePassword = async (current, next) => {
    await api.changePassword(session.token, current, next);
    setSession(null); setRows([]);
    setLoginMessage('Password berhasil diperbarui. Masuk kembali dengan password baru.');
  };

  useEffect(() => {
    if (!session || session.user.must_change_password) return;
    const controller = new AbortController();
    setLoading(true); setError('');
    api.summary(session.token, controller.signal).then((result) => setRows(result.data || [])).catch((failure) => {
      if (failure.name === 'AbortError') return;
      if (failure.status === 401) unauthorized(); else setError(failure.message);
    }).finally(() => { if (!controller.signal.aborted) setLoading(false); });
    return () => controller.abort();
  }, [session, refreshKey, unauthorized]);

  if (!session) return <LoginPage onLogin={login} message={loginMessage} />;
  if (session.user.must_change_password) return <PasswordPage onChange={changePassword} onLogout={logout} />;
  const isRegional = session.user.role_code === 'REGIONAL_MANAGER';
  const openDropPoint = (id) => { setSelectedId(id); setView('detail'); window.scrollTo({ top: 0, behavior: 'smooth' }); };
  const navigate = (target) => {
    if (target === 'detail' && !isRegional) setSelectedId(session.user.drop_points?.[0]?.drop_point_id || null);
    setView(target); window.scrollTo({ top: 0, behavior: 'smooth' });
  };
  const content = error && view !== 'report' ? <div className="page-content"><ErrorState message={error} onRetry={() => setRefreshKey((key) => key + 1)} /></div> : loading && !rows.length && view !== 'report' ? <LoadingState /> : view === 'overview' ? <OverviewPage rows={rows} token={session.token} onOpen={openDropPoint} onUnauthorized={unauthorized} /> : view === 'drop-points' ? <div className="page-content v2-page"><div className="v2-page-intro"><div><span className="v2-eyebrow">REGIONAL / LOKASI</span><h1>Drop Points</h1><p>Bandingkan kinerja dan buka halaman operasional setiap DP.</p></div></div><PerformanceTable rows={rows} onOpen={openDropPoint} /></div> : view === 'report' ? <ReportPage token={session.token} onOpen={openDropPoint} onUnauthorized={unauthorized} summaryRows={rows} /> : <DetailPage key={selectedId} id={selectedId} token={session.token} onBack={() => setView('drop-points')} onUnauthorized={unauthorized} isRegional={isRegional} />;
  return <Shell user={session.user} view={view} onNavigate={navigate} onLogout={logout} rows={rows} refresh={() => setRefreshKey((key) => key + 1)} refreshing={loading}>{content}</Shell>;
}
