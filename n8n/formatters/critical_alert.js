const alerts = Array.isArray($json.alerts) ? $json.alerts : [];
if (!alerts.length) {
  return [{ json: { has_alert: false, alert_count: 0, message: "" } }];
}

const severity = { CRITICAL: 2, WATCH: 1, NORMAL: 0 };
const number = value => value == null ? "-" : Number(value).toLocaleString("id-ID");
const percent = value => value == null ? "-" : `${Number(value).toLocaleString("id-ID", { maximumFractionDigits: 1 })}%`;
const hours = value => value == null ? "-" : `${Number(value).toLocaleString("id-ID", { maximumFractionDigits: 1 })} jam`;
const icon = status => status === "CRITICAL" ? "🔴" : status === "WATCH" ? "🟠" : "🟢";
const label = status => status === "CRITICAL" ? "KRITIS" : status === "WATCH" ? "WASPADA" : status === "NORMAL" ? "NORMAL" : "BELUM DIKETAHUI";
const components = [
  { key: "REVENUE", field: "revenue_status", name: "Pendapatan" },
  { key: "SELLER", field: "seller_status", name: "Seller" },
  { key: "PARCEL", field: "parcel_status", name: "Paket di DP" },
  { key: "DELIVERY", field: "delivery_status", name: "Pengiriman" }
];

function componentSection(alert, component, owners) {
  const lines = [`${icon(component.status)} ${component.name} · ${label(component.status)}`];
  switch (component.key) {
    case "REVENUE":
      lines.push(`💰 Pencapaian ${percent(alert.revenue_achievement_pct)} · ekspektasi ${percent(alert.expected_achievement_pct)} · selisih ${percent(alert.revenue_gap_pct)}`);
      break;
    case "SELLER":
      lines.push(`🏪 Normal ${number(alert.normal_seller)} · waspada ${number(alert.watch_seller)} · kritis ${number(alert.critical_seller)} · dipantau ${number(alert.total_monitored_seller)}`);
      break;
    case "PARCEL":
      lines.push(`📦 Di DP ${number(alert.parcel_at_dp)} · >24 jam ${number(alert.parcel_over_24h)} · terlama ${hours(alert.oldest_parcel_hours)}`);
      lines.push(`⏱ Rata-rata di DP ${hours(alert.avg_dp_hours)} · keluar ${percent(alert.parcel_out_pct)}`);
      break;
    case "DELIVERY":
      lines.push(`⏱ Tepat waktu ${percent(alert.on_time_rate_pct)} vs SLA ${percent(alert.delivery_sla_target_pct)}`);
      lines.push(`🚚 Terlambat ${number(alert.late_delivery)} · gagal ${number(alert.failed_delivery)} · retur ${number(alert.returned_delivery)} · lewat tenggat ${number(alert.overdue_delivery)}`);
      break;
  }
  const owner = owners.find(row => row.component === component.key);
  lines.push(owner
    ? `👤 PIC: ${owner.responsible_staff_name ?? "-"} · ${owner.responsible_unit_name ?? "-"}`
    : "👤 PIC: belum tersedia dalam data tanggung jawab");
  return lines.join("\n");
}

return alerts.flatMap(alert => {
  const owners = Array.isArray(alert.responsibility) ? alert.responsibility : [];
  const reasons = Array.isArray(alert.reasons) ? alert.reasons : [];
  const problems = components
    .map(component => ({ ...component, status: alert[component.field] }))
    .filter(component => severity[component.status] > 0)
    .sort((a, b) => severity[b.status] - severity[a.status]);
  const manager = alert.manager_name ?? "-";
  const title = [
    "🚨 PERINGATAN OPERASIONAL",
    `${alert.drop_point_name} · KRITIS`,
    "Data simulasi",
    `Status: ${label(alert.previous_status)} → KRITIS`,
    `Manager: ${manager}`
  ].join("\n");
  const sections = [
    ...problems.map(component => componentSection(alert, component, owners)),
    ...(reasons.length ? [["──────────", "⚠️ Alasan status kritis", ...reasons.map((reason, index) => `${index + 1}. ${reason}`)].join("\n")] : []),
    [
      "──────────",
      "🎯 Tindak lanjut",
      "1. Dahulukan komponen berstatus kritis.",
      "2. PIC terkait memeriksa penyebab dan mencatat tindakan.",
      `3. ${manager} memantau hasil dan mengeskalasi hambatan.`
    ].join("\n")
  ];
  const maxLength = 3400;
  const parts = [];
  let current = title;
  for (const section of sections) {
    const addition = `\n\n${section}`;
    if (current.length + addition.length > maxLength) {
      parts.push(current);
      current = `${title}\n\n${section}`;
    } else {
      current += addition;
    }
  }
  parts.push(current);
  return parts.map((part, index) => ({
    json: {
      has_alert: true,
      alert_count: alerts.length,
      drop_point_id: alert.drop_point_id,
      previous_status: alert.previous_status,
      current_status: alert.current_status,
      message: parts.length > 1 ? `${part}\n\nBagian ${index + 1}/${parts.length}` : part
    }
  }));
});
