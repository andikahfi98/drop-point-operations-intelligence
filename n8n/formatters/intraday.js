const rows = Array.isArray($json.data) ? $json.data : [];
const analysis = $json.analysis ?? {};
const severity = { CRITICAL: 2, WATCH: 1, NORMAL: 0 };
const attention = rows
  .filter(row => severity[row.overall_status] > 0)
  .sort((a, b) =>
    (severity[b.overall_status] - severity[a.overall_status]) ||
    String(a.drop_point_name ?? "").localeCompare(String(b.drop_point_name ?? ""))
  );

if (!attention.length) {
  return [{ json: { has_alert: false, alert_count: 0, message: "" } }];
}

const number = value => value == null ? "-" : Number(value).toLocaleString("id-ID");
const percent = value => value == null ? "-" : `${Number(value).toLocaleString("id-ID", { maximumFractionDigits: 1 })}%`;
const rupiah = value => value == null ? "-" : `Rp${Math.round(Number(value)).toLocaleString("id-ID")}`;
const hours = value => value == null ? "-" : `${Number(value).toLocaleString("id-ID", { maximumFractionDigits: 1 })} jam`;
const sum = field => rows.reduce((total, row) => total + Number(row[field] ?? 0), 0);
const date = value => {
  const parsed = new Date(`${String(value).slice(0, 10)}T00:00:00Z`);
  return Number.isNaN(parsed.getTime()) ? String(value) : new Intl.DateTimeFormat("id-ID", { day: "numeric", month: "long", year: "numeric", timeZone: "UTC" }).format(parsed);
};
const icon = status => status === "CRITICAL" ? "🔴" : status === "WATCH" ? "🟠" : "🟢";
const label = status => status === "CRITICAL" ? "KRITIS" : status === "WATCH" ? "WASPADA" : "NORMAL";
const flagged = status => severity[status] > 0;
const reportDate = attention[0].as_of_date ?? rows[0]?.as_of_date ?? "-";
const criticalCount = attention.filter(row => row.overall_status === "CRITICAL").length;
const watchCount = attention.length - criticalCount;

function overviewSection() {
  return [
    "📍 STATUS DROP POINT",
    ...attention.map(dp => [
      `${icon(dp.overall_status)} ${dp.drop_point_name} · ${label(dp.overall_status)}`,
      `📦 >24 jam ${number(dp.parcel_over_24h)} · 🚚 lewat tenggat ${number(dp.overdue_delivery)} · ⏱ tepat waktu ${percent(dp.on_time_rate_pct)}`
    ].join("\n"))
  ].join("\n\n");
}

function totalSection() {
  const completed = sum("completed_delivery");
  const onTime = completed ? percent(sum("on_time_delivery") / completed * 100) : "belum dapat dihitung";
  return [
    "📊 TOTAL OPERASIONAL",
    `📍 Drop point: ${number(rows.length)} (${criticalCount} kritis, ${watchCount} waspada)`,
    `💰 Pendapatan bulan berjalan: ${rupiah(sum("revenue"))}`,
    `📦 Paket di DP: ${number(sum("parcel_at_dp"))} · >24 jam: ${number(sum("parcel_over_24h"))}`,
    `🚚 Pengiriman selesai: ${number(completed)} · lewat tenggat: ${number(sum("overdue_delivery"))}`,
    `⏱ Tepat waktu regional: ${onTime}`
  ].join("\n");
}

function insightSection() {
  const items = Array.isArray(analysis.items) ? analysis.items.slice(0, 3) : [];
  if (!items.length) return "";
  const source = analysis.mode === "ai" ? "Insight AI" : "Insight operasional";
  return [
    `🧠 ${source} & tindakan`,
    ...items.flatMap((item, index) => [
      `${index + 1}. ${item.insight}`,
      `   Tindakan: ${item.action}`
    ])
  ].join("\n");
}

function pointSection(dp) {
  const actions = [];
  if (flagged(dp.revenue_status)) {
    actions.push({ status: dp.revenue_status, text: `Periksa selisih pendapatan dan seller penyumbangnya. Unit: Seller.` });
  }
  if (flagged(dp.seller_status)) {
    actions.push({ status: dp.seller_status, text: `Hubungi seller berstatus waspada/kritis. Unit: Seller.` });
  }
  if (flagged(dp.parcel_status)) {
    actions.push({ status: dp.parcel_status, text: `Dahulukan ${number(dp.parcel_over_24h)} paket >24 jam dan cek hambatan proses. Unit: Outbound.` });
  }
  if (flagged(dp.delivery_status)) {
    actions.push({ status: dp.delivery_status, text: `Tindak lanjuti ${number(dp.overdue_delivery)} pengiriman lewat tenggat dan kurir terkait. Unit: Delivery.` });
  }
  actions.sort((a, b) => severity[b.status] - severity[a.status]);
  const returned = dp.returned_delivery ?? dp.return_delivery;

  return [
    `${icon(dp.overall_status)} ${dp.drop_point_name} · ${label(dp.overall_status)}`,
    `Manager: ${dp.manager_name ?? "-"}`,
    "",
    `💰 Pendapatan: ${rupiah(dp.revenue)} / ${rupiah(dp.revenue_target)} (${percent(dp.revenue_achievement_pct)}) · ${label(dp.revenue_status)}`,
    `🏪 Seller aktif: ${number(dp.active_seller)}/${number(dp.active_seller_target)} · waspada ${number(dp.watch_seller)}, kritis ${number(dp.critical_seller)} · ${label(dp.seller_status)}`,
    "",
    "📦 Paket di DP",
    `Masuk/keluar bulan ini: ${number(dp.parcel_in_mtd)}/${number(dp.parcel_out_mtd)} · tertahan ${number(dp.parcel_at_dp)}`,
    `12–24 jam: ${number(dp.parcel_12_24h)} · >24 jam: ${number(dp.parcel_over_24h)} · terlama: ${hours(dp.oldest_parcel_hours)}`,
    `Rata-rata di DP: ${hours(dp.avg_dp_hours)} · keluar: ${percent(dp.parcel_out_pct)} · ${label(dp.parcel_status)}`,
    "",
    "🚚 Pengiriman",
    `Selesai/dalam perjalanan: ${number(dp.completed_delivery)}/${number(dp.in_transit_delivery)}`,
    `Tepat waktu/terlambat: ${number(dp.on_time_delivery)}/${number(dp.late_delivery)} · gagal ${number(dp.failed_delivery)} · retur ${number(returned)}`,
    `Lewat tenggat: ${number(dp.overdue_delivery)} · tepat waktu ${percent(dp.on_time_rate_pct)} vs SLA ${percent(dp.delivery_sla_target_pct)} · ${label(dp.delivery_status)}`,
    "",
    "🎯 Tindak lanjut",
    ...(actions.length ? actions.map((item, index) => `${index + 1}. [${label(item.status)}] ${item.text}`) : ["Tidak ada tindakan khusus."])
  ].join("\n");
}

const summary = [overviewSection(), totalSection(), insightSection()].filter(Boolean).join("\n\n──────────\n\n");
const sections = attention.map(pointSection);
const title = `📊 LAPORAN INTRADAY\n${date(reportDate)} | Data simulasi`;
const maxLength = 3400;
const parts = [`${title}\n\n──────────\n\n${summary}`];
let current = title;
for (const section of sections) {
  const addition = `\n\n──────────\n\n${section}`;
  if (current.length + addition.length > maxLength) {
    if (current !== title) parts.push(current);
    current = `${title}\n\n${section}`;
  } else {
    current += addition;
  }
}
if (current !== title) parts.push(current);

return parts.map((part, index) => ({
  json: {
    has_alert: true,
    alert_count: attention.length,
    message: parts.length > 1 ? `${part}\n\nBagian ${index + 1}/${parts.length}` : part,
    part: index + 1,
    total_parts: parts.length
  }
}));
