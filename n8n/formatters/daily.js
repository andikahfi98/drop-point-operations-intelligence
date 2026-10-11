const rows = Array.isArray($json.data) ? $json.data : [];
const analysis = $json.analysis ?? {};
const severity = { CRITICAL: 2, WATCH: 1, NORMAL: 0 };
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

if (!rows.length) {
  return [{ json: { message: "📋 LAPORAN HARIAN\nData simulasi belum tersedia.", total_drop_point: 0, attention_count: 0 } }];
}

const ordered = [...rows].sort((a, b) =>
  (severity[b.overall_status] - severity[a.overall_status]) ||
  String(a.drop_point_name ?? "").localeCompare(String(b.drop_point_name ?? ""))
);
const attention = ordered.filter(dp => flagged(dp.overall_status));
const criticalCount = attention.filter(dp => dp.overall_status === "CRITICAL").length;
const watchCount = attention.length - criticalCount;
const reportDate = $json.business_date ?? rows[0].business_date ?? "-";

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

function overviewSection() {
  return [
    "📍 STATUS DROP POINT",
    ...ordered.map(dp => [
      `${icon(dp.overall_status)} ${dp.drop_point_name} · ${label(dp.overall_status)}`,
      `💰 ${rupiah(dp.daily_revenue)} · 📦 >24 jam ${number(dp.parcel_over_24h)} · ⏱ tepat waktu MTD ${percent(dp.mtd_on_time_rate_pct)}`
    ].join("\n"))
  ].join("\n\n");
}

function totalSection() {
  const completed = sum("daily_completed");
  const onTime = completed ? percent(sum("daily_on_time") / completed * 100) : "belum dapat dihitung";
  return [
    "📊 TOTAL OPERASIONAL HARI INI",
    `📍 Drop point: ${number(rows.length)} (${criticalCount} kritis, ${watchCount} waspada)`,
    `📥 Paket masuk: ${number(sum("daily_parcel_in"))}`,
    `📤 Paket keluar: ${number(sum("daily_parcel_out"))}`,
    `🚚 Pengiriman: ${number(sum("daily_shipment"))} · selesai ${number(completed)}`,
    `⏰ Lewat tenggat: ${number(sum("daily_overdue"))}`,
    `💰 Pendapatan: ${rupiah(sum("daily_revenue"))}`,
    `⏱ Tepat waktu regional: ${onTime}`
  ].join("\n");
}

function pointSection(dp) {
  const actions = [];
  if (flagged(dp.parcel_status)) {
    actions.push({ status: dp.parcel_status, text: `Dahulukan ${number(dp.parcel_over_24h)} paket >24 jam; cek hambatan keluar DP. Unit: Outbound.` });
  }
  if (flagged(dp.delivery_status)) {
    actions.push({ status: dp.delivery_status, text: `Tindak lanjuti ${number(dp.mtd_overdue_delivery)} pengiriman lewat tenggat dan kendala kurir. Unit: Delivery.` });
  }
  if (flagged(dp.seller_status)) {
    actions.push({ status: dp.seller_status, text: `Hubungi seller berstatus waspada/kritis. Unit: Seller.` });
  }
  actions.sort((a, b) => severity[b.status] - severity[a.status]);
  const dailyOnTime = dp.daily_completed && dp.daily_on_time_rate_pct != null
    ? percent(dp.daily_on_time_rate_pct)
    : "belum dapat dihitung";
  const revenueGap = dp.revenue_gap_pct != null && Number(dp.revenue_gap_pct) < 0
    ? ` · tertinggal ${percent(Math.abs(Number(dp.revenue_gap_pct)))}`
    : "";

  return [
    `${icon(dp.overall_status)} ${dp.drop_point_name} · ${label(dp.overall_status)}`,
    `Manager: ${dp.manager_name ?? "-"}`,
    "",
    "📅 Hari ini",
    `Pendapatan: ${rupiah(dp.daily_revenue)} / ${rupiah(dp.daily_revenue_target)} (${percent(dp.daily_revenue_achievement_pct)}) · ${number(dp.daily_invoice)} invoice`,
    `Seller aktif: ${number(dp.daily_active_seller)} · paket masuk/keluar: ${number(dp.daily_parcel_in)}/${number(dp.daily_parcel_out)}`,
    `Pengiriman: ${number(dp.daily_shipment)} · selesai ${number(dp.daily_completed)} · dalam perjalanan ${number(dp.daily_in_transit)}`,
    `Tepat waktu/terlambat: ${number(dp.daily_on_time)}/${number(dp.daily_late)} · gagal ${number(dp.daily_failed)} · retur ${number(dp.daily_returned)} · lewat tenggat ${number(dp.daily_overdue)}`,
    `Tepat waktu hari ini: ${dailyOnTime}`,
    "",
    "📈 Bulan berjalan",
    `Pendapatan: ${rupiah(dp.mtd_revenue)} / ${rupiah(dp.monthly_revenue_target)} (${percent(dp.mtd_revenue_achievement_pct)}; ekspektasi ${percent(dp.expected_achievement_pct)}${revenueGap})`,
    `Seller: normal ${number(dp.normal_seller)} · waspada ${number(dp.watch_seller)} · kritis ${number(dp.critical_seller)} · ${label(dp.seller_status)}`,
    `Paket di DP: ${number(dp.parcel_at_dp)} · >24 jam ${number(dp.parcel_over_24h)} · terlama ${hours(dp.oldest_parcel_hours)} · ${label(dp.parcel_status)}`,
    `Rata-rata di DP: ${hours(dp.avg_dp_hours)} · keluar ${percent(dp.parcel_out_pct)}`,
    `Pengiriman: selesai ${number(dp.mtd_completed_delivery)} · dalam perjalanan ${number(dp.mtd_in_transit_delivery)} · terlambat ${number(dp.mtd_late_delivery)}`,
    `Gagal ${number(dp.mtd_failed_delivery)} · retur ${number(dp.mtd_returned_delivery)} · lewat tenggat ${number(dp.mtd_overdue_delivery)}`,
    `Tepat waktu MTD ${percent(dp.mtd_on_time_rate_pct)} vs SLA ${percent(dp.delivery_sla_target_pct)} · ${label(dp.delivery_status)}`,
    "",
    "🎯 Tindak lanjut",
    ...(actions.length ? actions.map((item, index) => `${index + 1}. [${label(item.status)}] ${item.text}`) : ["Tidak ada tindakan khusus."])
  ].join("\n");
}

const title = `📋 LAPORAN HARIAN DROP POINT\n${date(reportDate)} | Data simulasi`;
const summary = [overviewSection(), totalSection(), insightSection()].filter(Boolean).join("\n\n──────────\n\n");
const sections = attention.map(pointSection);
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
    message: parts.length > 1 ? `${part}\n\nBagian ${index + 1}/${parts.length}` : part,
    part: index + 1,
    total_parts: parts.length,
    total_drop_point: rows.length,
    attention_count: attention.length
  }
}));
