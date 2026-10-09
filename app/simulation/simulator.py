import json

import random

from datetime import date, datetime, time, timedelta

from decimal import Decimal, ROUND_HALF_UP



from sqlalchemy import text



from app.db.database import engine





SIMULATION_NAME = "operations_demo"

INTERVAL_MINUTES = 5

WORK_START = time(8, 0)

WORK_END = time(16, 55)





# ============================================================

# DROP POINT BEHAVIOUR

# Revenue = shipping fee income.

# Parcel backlog is simulated independently from delivery SLA.

# ============================================================



DP_PROFILE = {

    "DP-TGR-01": {

        "revenue_factor": 0.75,

        "late_rate": 0.20,

        "failed_rate": 0.07,

        "backlog_rate": 0.24,

        "backlog_hours": (24, 52),

    },

    "DP-BKS-01": {

        "revenue_factor": 0.85,

        "late_rate": 0.12,

        "failed_rate": 0.04,

        "backlog_rate": 0.12,

        "backlog_hours": (14, 30),

    },

    "DP-DPK-01": {

        "revenue_factor": 1.00,

        "late_rate": 0.05,

        "failed_rate": 0.01,

        "backlog_rate": 0.03,

        "backlog_hours": (8, 18),

    },

    "DP-BGR-01": {

        "revenue_factor": 1.05,

        "late_rate": 0.06,

        "failed_rate": 0.02,

        "backlog_rate": 0.04,

        "backlog_hours": (8, 20),

    },

    "DP-JKTT-01": {

        "revenue_factor": 1.10,

        "late_rate": 0.03,

        "failed_rate": 0.01,

        "backlog_rate": 0.02,

        "backlog_hours": (6, 16),

    },

    "DP-JKTB-01": {

        "revenue_factor": 1.15,

        "late_rate": 0.05,

        "failed_rate": 0.01,

        "backlog_rate": 0.03,

        "backlog_hours": (6, 18),

    },

}



DEFAULT_PROFILE = {

    "revenue_factor": 1.00,

    "late_rate": 0.05,

    "failed_rate": 0.01,

    "backlog_rate": 0.03,

    "backlog_hours": (8, 18),

}



BACKLOG_REASONS = [

    "OPERATIONAL_DELAY",

    "CAPACITY_ISSUE",

    "LINEHAUL_DELAY",

]



DELIVERY_FAILURE_REASONS = [

    "RECEIVER_UNAVAILABLE",

    "ADDRESS_ISSUE",

    "VEHICLE_ISSUE",

    "OTHER",

]



DELIVERY_LATE_REASONS = [

    "OPERATIONAL_DELAY",

    "VEHICLE_ISSUE",

]



LOCAL_DESTINATION_RATE = 0.30

LINEHAUL_HOURS = (2.0, 8.0)

DESTINATION_RELEASE_HOURS = (0.5, 5.0)

# Linehaul and destination receiving may happen overnight, but courier
# dispatch and last-mile completion should remain in realistic field hours.
COURIER_DISPATCH_START = time(7, 0)
COURIER_DISPATCH_END = time(18, 0)
LAST_MILE_START = time(8, 0)
LAST_MILE_END = time(21, 0)





def money(value):

    return Decimal(value).quantize(

        Decimal("0.01"),

        rounding=ROUND_HALF_UP,

    )





def raw_value(value):

    if value is None:

        return None

    if isinstance(value, bool):

        return "Y" if value else "N"

    return str(value)





# ============================================================

# SIMULATION CLOCK

# ============================================================



def get_next_working_date(connection, current_date):

    row = connection.execute(

        text("""

            SELECT date

            FROM core.dim_date

            WHERE date > :current_date

              AND is_working_day = TRUE

            ORDER BY date

            LIMIT 1;

        """),

        {"current_date": current_date},

    ).fetchone()



    if row is None:

        raise RuntimeError(

            "No future working date available in core.dim_date."

        )



    return row[0]





def _is_working_date(connection, candidate_date):

    row = connection.execute(

        text("""

            SELECT is_working_day

            FROM core.dim_date

            WHERE date = :candidate_date

            LIMIT 1;

        """),

        {"candidate_date": candidate_date},

    ).fetchone()



    return bool(row and row[0])




def _fit_to_operating_window(connection, candidate_ts, window_start, window_end):

    """Move a field event into the next valid operating window."""

    adjusted = candidate_ts



    for _ in range(14):

        if not _is_working_date(connection, adjusted.date()):

            next_date = get_next_working_date(connection, adjusted.date())

            adjusted = datetime.combine(next_date, window_start)

            continue



        if adjusted.time() < window_start:

            return datetime.combine(adjusted.date(), window_start)



        if adjusted.time() <= window_end:

            return adjusted



        overflow = adjusted - datetime.combine(adjusted.date(), window_end)

        next_date = get_next_working_date(connection, adjusted.date())

        adjusted = datetime.combine(next_date, window_start) + overflow



    raise RuntimeError("Could not fit event into operating window.")




def get_next_simulation_point(connection, current_date, current_time):

    current_ts = datetime.combine(current_date, current_time)

    next_ts = current_ts + timedelta(minutes=INTERVAL_MINUTES)



    if next_ts.time() <= WORK_END:

        return current_date, next_ts.time()



    return get_next_working_date(connection, current_date), WORK_START





# ============================================================

# INTRADAY REVENUE WEIGHT

# ============================================================



def get_time_weight(business_time):

    if business_time < time(10, 0):

        return Decimal("0.70")

    if business_time < time(12, 0):

        return Decimal("1.10")

    if business_time < time(13, 0):

        return Decimal("0.65")

    if business_time < time(15, 0):

        return Decimal("1.15")

    return Decimal("1.35")





def get_total_daily_weight():

    cursor = datetime.combine(date(2000, 1, 1), WORK_START)

    end = datetime.combine(date(2000, 1, 1), WORK_END)

    total = Decimal("0")



    while cursor <= end:

        total += get_time_weight(cursor.time())

        cursor += timedelta(minutes=INTERVAL_MINUTES)



    return total





TOTAL_DAILY_WEIGHT = get_total_daily_weight()





# ============================================================

# MONTHLY TARGETS

# SELLER UNIT: revenue + active seller coverage

# DROP POINT: delivery SLA

# ============================================================



def ensure_month_targets(connection, business_date):
    """Ensure monthly Seller-unit and delivery targets exist.

    Seller targets are stored per Seller-unit PIC/staff. Delivery SLA targets
    remain at Drop Point level. When a new month starts, targets are rolled
    forward from the latest prior month.
    """
    month_start = business_date.replace(day=1)
    inserted_rows = 0

    seller_target_count = connection.execute(
        text("""
            SELECT COUNT(*)
            FROM core.fact_seller_target
            WHERE month_start = :month_start;
        """),
        {"month_start": month_start},
    ).scalar_one()

    if seller_target_count == 0:
        previous_month = connection.execute(
            text("""
                SELECT MAX(month_start)
                FROM core.fact_seller_target
                WHERE month_start < :month_start;
            """),
            {"month_start": month_start},
        ).scalar_one()

        if previous_month is None:
            raise RuntimeError("Previous seller target month not found.")

        connection.execute(
            text("""
                INSERT INTO core.fact_seller_target (
                    month_start,
                    drop_point_id,
                    staff_id,
                    revenue_target,
                    active_seller_target
                )
                SELECT
                    :month_start,
                    drop_point_id,
                    staff_id,
                    ROUND(revenue_target * 1.03, 2),
                    active_seller_target
                FROM core.fact_seller_target
                WHERE month_start = :previous_month
                ON CONFLICT (month_start, drop_point_id, staff_id)
                DO NOTHING;
            """),
            {
                "month_start": month_start,
                "previous_month": previous_month,
            },
        )

        connection.execute(
            text("""
                INSERT INTO raw.fact_seller_target (
                    month_start,
                    drop_point_id,
                    staff_id,
                    revenue_target,
                    active_seller_target
                )
                SELECT
                    month_start::text,
                    drop_point_id,
                    staff_id,
                    revenue_target::text,
                    active_seller_target::text
                FROM core.fact_seller_target
                WHERE month_start = :month_start;
            """),
            {"month_start": month_start},
        )

        inserted_rows += connection.execute(
            text("""
                SELECT COUNT(*)
                FROM core.fact_seller_target
                WHERE month_start = :month_start;
            """),
            {"month_start": month_start},
        ).scalar_one()

    delivery_target_count = connection.execute(
        text("""
            SELECT COUNT(*)
            FROM core.fact_delivery_target
            WHERE month_start = :month_start;
        """),
        {"month_start": month_start},
    ).scalar_one()

    if delivery_target_count == 0:
        previous_month = connection.execute(
            text("""
                SELECT MAX(month_start)
                FROM core.fact_delivery_target
                WHERE month_start < :month_start;
            """),
            {"month_start": month_start},
        ).scalar_one()

        if previous_month is None:
            raise RuntimeError("Previous delivery target month not found.")

        connection.execute(
            text("""
                INSERT INTO core.fact_delivery_target (
                    month_start,
                    drop_point_id,
                    delivery_sla_target_pct
                )
                SELECT
                    :month_start,
                    drop_point_id,
                    delivery_sla_target_pct
                FROM core.fact_delivery_target
                WHERE month_start = :previous_month
                ON CONFLICT (month_start, drop_point_id)
                DO NOTHING;
            """),
            {
                "month_start": month_start,
                "previous_month": previous_month,
            },
        )

        connection.execute(
            text("""
                INSERT INTO raw.fact_delivery_target (
                    month_start,
                    drop_point_id,
                    delivery_sla_target_pct
                )
                SELECT
                    month_start::text,
                    drop_point_id,
                    delivery_sla_target_pct::text
                FROM core.fact_delivery_target
                WHERE month_start = :month_start;
            """),
            {"month_start": month_start},
        )

        inserted_rows += connection.execute(
            text("""
                SELECT COUNT(*)
                FROM core.fact_delivery_target
                WHERE month_start = :month_start;
            """),
            {"month_start": month_start},
        ).scalar_one()

    return inserted_rows



# ============================================================

# REVENUE

# Grain: 1 row = 1 shipping invoice / shipping fee transaction.

# ============================================================



def generate_revenue_batch(connection, simulation_ts, batch_no, rng):
    """Generate shipping-fee revenue and invoice headers.

    Revenue belongs to a Seller served by the origin Drop Point. It is shipping
    fee income only; merchandise/COD value is not simulated as revenue.
    """
    business_date = simulation_ts.date()
    business_time = simulation_ts.time()
    month_start = business_date.replace(day=1)

    working_days = connection.execute(
        text("""
            SELECT COUNT(*)
            FROM core.dim_date
            WHERE month_start = :month_start
              AND is_working_day = TRUE;
        """),
        {"month_start": month_start},
    ).scalar_one()

    if working_days <= 0:
        raise RuntimeError("No working days found for current month.")

    targets = connection.execute(
        text("""
            SELECT
                drop_point_id,
                SUM(revenue_target) AS revenue_target
            FROM core.fact_seller_target
            WHERE month_start = :month_start
            GROUP BY drop_point_id;
        """),
        {"month_start": month_start},
    ).mappings().all()

    sellers = connection.execute(
        text("""
            SELECT
                seller_id,
                drop_point_id,
                seller_pic_id
            FROM core.dim_seller
            WHERE active_flag = TRUE;
        """)
    ).mappings().all()

    sellers_by_dp = {}
    for seller in sellers:
        sellers_by_dp.setdefault(seller["drop_point_id"], []).append(seller)

    revenue_rows = []
    invoice_headers = []
    invoice_counter = 0
    time_weight = get_time_weight(business_time)

    for target in targets:
        drop_point_id = target["drop_point_id"]
        dp_sellers = sellers_by_dp.get(drop_point_id, [])

        if not dp_sellers:
            continue

        if rng.random() < 0.05:
            continue

        profile = DP_PROFILE.get(drop_point_id, DEFAULT_PROFILE)
        monthly_target = Decimal(target["revenue_target"])

        interval_target = (
            monthly_target
            / Decimal(working_days)
            * Decimal(str(profile["revenue_factor"]))
            * time_weight
            / TOTAL_DAILY_WEIGHT
        )

        interval_total = money(
            interval_target * Decimal(str(rng.uniform(0.85, 1.15)))
        )

        if interval_total <= 0:
            continue

        invoice_count = rng.choices(
            [1, 2, 3],
            weights=[60, 30, 10],
            k=1,
        )[0]

        weights = [rng.uniform(0.6, 1.4) for _ in range(invoice_count)]
        weight_total = sum(weights)
        allocated = Decimal("0")

        for index in range(invoice_count):
            invoice_counter += 1
            seller = rng.choice(dp_sellers)

            invoice_id = (
                f"SIM-{business_date:%Y%m%d}"
                f"-{business_time:%H%M}"
                f"-B{batch_no:05d}"
                f"-I{invoice_counter:03d}"
            )

            if index == invoice_count - 1:
                revenue = money(interval_total - allocated)
            else:
                share = Decimal(str(weights[index] / weight_total))
                revenue = money(interval_total * share)
                allocated += revenue

            if revenue < 0:
                revenue = Decimal("0.00")

            row = {
                "revenue_date": business_date,
                "transaction_ts": simulation_ts,
                "invoice_id": invoice_id,
                "drop_point_id": drop_point_id,
                "seller_pic_id": seller["seller_pic_id"],
                "seller_id": seller["seller_id"],
                "revenue": revenue,
            }

            revenue_rows.append(row)
            invoice_headers.append({
                "invoice_id": invoice_id,
                "origin_dp_id": drop_point_id,
                "seller_id": seller["seller_id"],
            })

    if not revenue_rows:
        return revenue_rows, invoice_headers

    connection.execute(
        text("""
            INSERT INTO core.fact_revenue (
                revenue_date,
                transaction_ts,
                invoice_id,
                drop_point_id,
                seller_pic_id,
                seller_id,
                revenue
            )
            VALUES (
                :revenue_date,
                :transaction_ts,
                :invoice_id,
                :drop_point_id,
                :seller_pic_id,
                :seller_id,
                :revenue
            );
        """),
        revenue_rows,
    )

    raw_rows = [
        {
            "revenue_date": raw_value(row["revenue_date"]),
            "transaction_ts": raw_value(row["transaction_ts"]),
            "invoice_id": row["invoice_id"],
            "drop_point_id": row["drop_point_id"],
            "seller_pic_id": row["seller_pic_id"],
            "seller_id": row["seller_id"],
            "revenue": raw_value(row["revenue"]),
        }
        for row in revenue_rows
    ]

    connection.execute(
        text("""
            INSERT INTO raw.fact_revenue (
                revenue_date,
                transaction_ts,
                invoice_id,
                drop_point_id,
                seller_pic_id,
                seller_id,
                revenue
            )
            VALUES (
                :revenue_date,
                :transaction_ts,
                :invoice_id,
                :drop_point_id,
                :seller_pic_id,
                :seller_id,
                :revenue
            );
        """),
        raw_rows,
    )

    return revenue_rows, invoice_headers



# ============================================================
# SHIPMENT / PARCEL LIFECYCLE
# ============================================================


def _get_parcel_plan(shipment_id, drop_point_id, stage="origin"):
    """Deterministic processing/release plan for a parcel at a Drop Point."""
    profile = DP_PROFILE.get(drop_point_id, DEFAULT_PROFILE)
    plan_rng = random.Random(
        f"{SIMULATION_NAME}|{shipment_id}|parcel_flow|{stage}"
    )

    sort_minutes = plan_rng.randint(10, 75)
    is_backlog = plan_rng.random() < profile["backlog_rate"]

    if is_backlog:
        min_hours, max_hours = profile["backlog_hours"]
        release_hours = plan_rng.uniform(min_hours, max_hours)
        if stage == "destination":
            parcel_issue_reason = plan_rng.choice([
                "OPERATIONAL_DELAY",
                "CAPACITY_ISSUE",
            ])
        else:
            parcel_issue_reason = plan_rng.choice(BACKLOG_REASONS)
    else:
        if stage == "destination":
            min_hours, max_hours = DESTINATION_RELEASE_HOURS
            release_hours = plan_rng.uniform(min_hours, max_hours)
        else:
            release_hours = plan_rng.uniform(1.0, 6.0)
        parcel_issue_reason = None

    release_minutes = max(
        sort_minutes + 15 if stage == "origin" else 15,
        int(round(release_hours * 60)),
    )

    return {
        "sort_minutes": sort_minutes,
        "release_minutes": release_minutes,
        "parcel_issue_reason": parcel_issue_reason,
    }


def _get_linehaul_plan(shipment_id, origin_dp_id, destination_dp_id):
    """Deterministic inter-DP transit plan."""
    if origin_dp_id == destination_dp_id:
        return {
            "linehaul_hours": 0.0,
            "delivery_issue_reason": None,
        }

    plan_rng = random.Random(
        f"{SIMULATION_NAME}|{shipment_id}|linehaul"
    )
    min_hours, max_hours = LINEHAUL_HOURS
    linehaul_hours = plan_rng.uniform(min_hours, max_hours)

    # A small share gets a genuine linehaul exception.
    if plan_rng.random() < 0.08:
        linehaul_hours += plan_rng.uniform(4.0, 16.0)
        reason = "LINEHAUL_DELAY"
    else:
        reason = None

    return {
        "linehaul_hours": linehaul_hours,
        "delivery_issue_reason": reason,
    }


def _get_delivery_outcome_plan(shipment_id, destination_dp_id, sla_hours):
    """Deterministic last-mile outcome measured from origin release time."""
    profile = DP_PROFILE.get(destination_dp_id, DEFAULT_PROFILE)
    outcome_rng = random.Random(
        f"{SIMULATION_NAME}|{shipment_id}|delivery_outcome"
    )

    failed_rate = profile["failed_rate"]
    late_rate = profile["late_rate"]
    random_value = outcome_rng.random()

    if random_value < failed_rate:
        return {
            "planned_status": "FAILED",
            "network_hours": sla_hours + outcome_rng.randint(4, 24),
            "attempt_count": outcome_rng.choice([2, 3]),
            "delivery_issue_reason": outcome_rng.choice(DELIVERY_FAILURE_REASONS),
        }

    if random_value < failed_rate + late_rate:
        return {
            "planned_status": "DELIVERED",
            "network_hours": sla_hours + outcome_rng.randint(2, 36),
            "attempt_count": outcome_rng.choice([1, 2]),
            "delivery_issue_reason": outcome_rng.choice(DELIVERY_LATE_REASONS),
        }

    minimum_hours = max(4, int(sla_hours * 0.30))
    maximum_hours = max(minimum_hours, sla_hours - 2)

    return {
        "planned_status": "DELIVERED",
        "network_hours": outcome_rng.randint(minimum_hours, maximum_hours),
        "attempt_count": 1,
        "delivery_issue_reason": None,
    }


def _get_return_plan(shipment_id, delivery_issue_reason):
    """Plan return-to-seller after a terminal failed last-mile attempt."""
    plan_rng = random.Random(
        f"{SIMULATION_NAME}|{shipment_id}|return"
    )

    if delivery_issue_reason == "ADDRESS_ISSUE":
        reasons = ["ADDRESS_INVALID", "OTHER"]
    elif delivery_issue_reason == "RECEIVER_UNAVAILABLE":
        reasons = ["MAX_ATTEMPT", "RECEIVER_REJECTED"]
    else:
        reasons = ["MAX_ATTEMPT", "DAMAGED", "OTHER"]

    return {
        "return_delay_hours": plan_rng.uniform(8.0, 30.0),
        "return_reason": plan_rng.choice(reasons),
    }


def _pick_courier(connection, destination_dp_id, shipment_id):
    couriers = connection.execute(
        text("""
            SELECT courier_id
            FROM core.dim_courier
            WHERE drop_point_id = :drop_point_id
              AND active_flag = TRUE
            ORDER BY courier_id;
        """),
        {"drop_point_id": destination_dp_id},
    ).scalars().all()

    if not couriers:
        raise RuntimeError(
            f"No active courier found for destination DP {destination_dp_id}."
        )

    pick_rng = random.Random(
        f"{SIMULATION_NAME}|{shipment_id}|courier"
    )
    return pick_rng.choice(couriers)


def _update_raw_shipment(connection, shipment_id, values):
    assignments = []
    params = {"shipment_id": shipment_id}

    for key, value in values.items():
        assignments.append(f"{key} = :{key}")
        params[key] = raw_value(value)

    if not assignments:
        return

    connection.execute(
        text(
            "UPDATE raw.fact_shipment SET "
            + ", ".join(assignments)
            + " WHERE shipment_id = :shipment_id"
        ),
        params,
    )


def advance_shipments(connection, simulation_ts):
    """Advance open shipments through origin, linehaul, destination and last mile."""
    shipments = connection.execute(
        text("""
            SELECT
                shipment_id,
                origin_dp_id,
                destination_dp_id,
                received_ts,
                sorted_ts,
                left_dp_ts,
                arrived_destination_ts,
                out_for_delivery_ts,
                target_delivery_ts,
                actual_delivery_ts,
                returned_ts,
                courier_id,
                shipment_status,
                sla_hours,
                attempt_count,
                parcel_issue_reason,
                delivery_issue_reason,
                return_reason
            FROM core.fact_shipment
            WHERE shipment_status IN (
                'RECEIVED',
                'SORTING',
                'READY',
                'IN_TRANSIT',
                'ARRIVED_DESTINATION',
                'OUT_FOR_DELIVERY',
                'FAILED'
            )
              AND received_ts IS NOT NULL
              AND received_ts <= :simulation_ts
            ORDER BY received_ts, shipment_id;
        """),
        {"simulation_ts": simulation_ts},
    ).mappings().all()

    left_dp_count = 0
    completed_count = 0

    for shipment_row in shipments:
        shipment = dict(shipment_row)
        shipment_id = shipment["shipment_id"]
        status = shipment["shipment_status"]
        origin_dp_id = shipment["origin_dp_id"]
        destination_dp_id = shipment["destination_dp_id"]

        # --------------------------------------------------------
        # Origin Drop Point: RECEIVED -> SORTING -> READY -> leave
        # --------------------------------------------------------
        if status in {"RECEIVED", "SORTING", "READY"}:
            parcel_plan = _get_parcel_plan(
                shipment_id,
                origin_dp_id,
                stage="origin",
            )

            sort_ts = shipment["received_ts"] + timedelta(
                minutes=parcel_plan["sort_minutes"]
            )
            release_ts = shipment["received_ts"] + timedelta(
                minutes=parcel_plan["release_minutes"]
            )

            if simulation_ts >= release_ts:
                target_delivery_ts = release_ts + timedelta(
                    hours=shipment["sla_hours"]
                )
                linehaul_plan = _get_linehaul_plan(
                    shipment_id,
                    origin_dp_id,
                    destination_dp_id,
                )

                values = {
                    "sorted_ts": shipment["sorted_ts"] or sort_ts,
                    "left_dp_ts": release_ts,
                    "target_delivery_ts": target_delivery_ts,
                    "parcel_issue_reason": None,
                }

                if origin_dp_id == destination_dp_id:
                    out_for_delivery_ts = _fit_to_operating_window(
                        connection,
                        release_ts,
                        COURIER_DISPATCH_START,
                        COURIER_DISPATCH_END,
                    )
                    values.update({
                        "arrived_destination_ts": release_ts,
                        "out_for_delivery_ts": out_for_delivery_ts,
                        "courier_id": shipment["courier_id"] or _pick_courier(
                            connection,
                            destination_dp_id,
                            shipment_id,
                        ),
                        "shipment_status": "OUT_FOR_DELIVERY",
                    })
                else:
                    values.update({
                        "shipment_status": "IN_TRANSIT",
                        "delivery_issue_reason": (
                            linehaul_plan["delivery_issue_reason"]
                            or shipment["delivery_issue_reason"]
                        ),
                    })

                connection.execute(
                    text("""
                        UPDATE core.fact_shipment
                        SET
                            sorted_ts = :sorted_ts,
                            left_dp_ts = :left_dp_ts,
                            arrived_destination_ts = COALESCE(
                                :arrived_destination_ts,
                                arrived_destination_ts
                            ),
                            out_for_delivery_ts = COALESCE(
                                :out_for_delivery_ts,
                                out_for_delivery_ts
                            ),
                            target_delivery_ts = :target_delivery_ts,
                            courier_id = COALESCE(:courier_id, courier_id),
                            shipment_status = :shipment_status,
                            parcel_issue_reason = :parcel_issue_reason,
                            delivery_issue_reason = COALESCE(
                                :delivery_issue_reason,
                                delivery_issue_reason
                            )
                        WHERE shipment_id = :shipment_id;
                    """),
                    {
                        "shipment_id": shipment_id,
                        "arrived_destination_ts": values.get("arrived_destination_ts"),
                        "out_for_delivery_ts": values.get("out_for_delivery_ts"),
                        "courier_id": values.get("courier_id"),
                        "delivery_issue_reason": values.get("delivery_issue_reason"),
                        **values,
                    },
                )
                _update_raw_shipment(connection, shipment_id, values)
                left_dp_count += 1

                shipment.update(values)
                status = shipment["shipment_status"]

            elif simulation_ts >= sort_ts:
                values = {
                    "sorted_ts": shipment["sorted_ts"] or sort_ts,
                    "shipment_status": "READY",
                    "parcel_issue_reason": parcel_plan["parcel_issue_reason"],
                }

                connection.execute(
                    text("""
                        UPDATE core.fact_shipment
                        SET
                            sorted_ts = :sorted_ts,
                            shipment_status = :shipment_status,
                            parcel_issue_reason = :parcel_issue_reason
                        WHERE shipment_id = :shipment_id;
                    """),
                    {"shipment_id": shipment_id, **values},
                )
                _update_raw_shipment(connection, shipment_id, values)
                continue

            elif simulation_ts >= shipment["received_ts"] + timedelta(minutes=5):
                values = {
                    "shipment_status": "SORTING",
                    "parcel_issue_reason": None,
                }
                connection.execute(
                    text("""
                        UPDATE core.fact_shipment
                        SET
                            shipment_status = :shipment_status,
                            parcel_issue_reason = :parcel_issue_reason
                        WHERE shipment_id = :shipment_id;
                    """),
                    {"shipment_id": shipment_id, **values},
                )
                _update_raw_shipment(connection, shipment_id, values)
                continue
            else:
                continue

        # --------------------------------------------------------
        # Inter-DP linehaul: IN_TRANSIT -> ARRIVED_DESTINATION
        # --------------------------------------------------------
        if status == "IN_TRANSIT":
            if shipment.get("left_dp_ts") is None:
                continue

            linehaul_plan = _get_linehaul_plan(
                shipment_id,
                origin_dp_id,
                destination_dp_id,
            )
            arrival_ts = shipment["left_dp_ts"] + timedelta(
                hours=linehaul_plan["linehaul_hours"]
            )

            if simulation_ts < arrival_ts:
                continue

            destination_plan = _get_parcel_plan(
                shipment_id,
                destination_dp_id,
                stage="destination",
            )
            values = {
                "arrived_destination_ts": arrival_ts,
                "shipment_status": "ARRIVED_DESTINATION",
                "parcel_issue_reason": destination_plan["parcel_issue_reason"],
            }
            connection.execute(
                text("""
                    UPDATE core.fact_shipment
                    SET
                        arrived_destination_ts = :arrived_destination_ts,
                        shipment_status = :shipment_status,
                        parcel_issue_reason = :parcel_issue_reason
                    WHERE shipment_id = :shipment_id;
                """),
                {"shipment_id": shipment_id, **values},
            )
            _update_raw_shipment(connection, shipment_id, values)
            shipment.update(values)
            status = "ARRIVED_DESTINATION"

        # --------------------------------------------------------
        # Destination DP: ARRIVED_DESTINATION -> OUT_FOR_DELIVERY
        # --------------------------------------------------------
        if status == "ARRIVED_DESTINATION":
            arrival_ts = shipment.get("arrived_destination_ts")
            if arrival_ts is None:
                continue

            destination_plan = _get_parcel_plan(
                shipment_id,
                destination_dp_id,
                stage="destination",
            )
            out_for_delivery_ts = arrival_ts + timedelta(
                minutes=destination_plan["release_minutes"]
            )
            out_for_delivery_ts = _fit_to_operating_window(
                connection,
                out_for_delivery_ts,
                COURIER_DISPATCH_START,
                COURIER_DISPATCH_END,
            )

            if simulation_ts < out_for_delivery_ts:
                continue

            values = {
                "out_for_delivery_ts": out_for_delivery_ts,
                "courier_id": shipment["courier_id"] or _pick_courier(
                    connection,
                    destination_dp_id,
                    shipment_id,
                ),
                "shipment_status": "OUT_FOR_DELIVERY",
                "parcel_issue_reason": None,
            }
            connection.execute(
                text("""
                    UPDATE core.fact_shipment
                    SET
                        out_for_delivery_ts = :out_for_delivery_ts,
                        courier_id = :courier_id,
                        shipment_status = :shipment_status,
                        parcel_issue_reason = :parcel_issue_reason
                    WHERE shipment_id = :shipment_id;
                """),
                {"shipment_id": shipment_id, **values},
            )
            _update_raw_shipment(connection, shipment_id, values)
            shipment.update(values)
            status = "OUT_FOR_DELIVERY"

        # --------------------------------------------------------
        # Last mile: OUT_FOR_DELIVERY -> DELIVERED / FAILED
        # --------------------------------------------------------
        if status == "OUT_FOR_DELIVERY":
            left_dp_ts = shipment.get("left_dp_ts")
            out_for_delivery_ts = shipment.get("out_for_delivery_ts")
            target_delivery_ts = shipment.get("target_delivery_ts")

            if (
                left_dp_ts is None
                or out_for_delivery_ts is None
                or target_delivery_ts is None
            ):
                continue

            outcome = _get_delivery_outcome_plan(
                shipment_id,
                destination_dp_id,
                shipment["sla_hours"],
            )

            planned_event_ts = left_dp_ts + timedelta(
                hours=outcome["network_hours"]
            )

            # Delivery cannot finish before the parcel is actually out for delivery.
            minimum_last_mile_ts = out_for_delivery_ts + timedelta(hours=1)
            event_ts = max(planned_event_ts, minimum_last_mile_ts)
            event_ts = _fit_to_operating_window(
                connection,
                event_ts,
                LAST_MILE_START,
                LAST_MILE_END,
            )

            if simulation_ts < event_ts:
                continue

            if outcome["planned_status"] == "FAILED":
                values = {
                    "actual_delivery_ts": None,
                    "shipment_status": "FAILED",
                    "attempt_count": outcome["attempt_count"],
                    "delivery_issue_reason": outcome["delivery_issue_reason"],
                }
            else:
                is_late = event_ts > target_delivery_ts
                values = {
                    "actual_delivery_ts": event_ts,
                    "shipment_status": "DELIVERED",
                    "attempt_count": outcome["attempt_count"],
                    "delivery_issue_reason": (
                        outcome["delivery_issue_reason"] if is_late
                        else shipment.get("delivery_issue_reason")
                    ),
                }

            connection.execute(
                text("""
                    UPDATE core.fact_shipment
                    SET
                        actual_delivery_ts = :actual_delivery_ts,
                        shipment_status = :shipment_status,
                        attempt_count = :attempt_count,
                        delivery_issue_reason = :delivery_issue_reason
                    WHERE shipment_id = :shipment_id;
                """),
                {"shipment_id": shipment_id, **values},
            )
            _update_raw_shipment(connection, shipment_id, values)
            completed_count += 1
            shipment.update(values)
            status = shipment["shipment_status"]

        # --------------------------------------------------------
        # Failed terminal attempt -> RETURN_TO_SELLER
        # --------------------------------------------------------
        if status == "FAILED":
            left_dp_ts = shipment.get("left_dp_ts")
            if left_dp_ts is None:
                continue

            outcome = _get_delivery_outcome_plan(
                shipment_id,
                destination_dp_id,
                shipment["sla_hours"],
            )
            failed_ts = left_dp_ts + timedelta(
                hours=outcome["network_hours"]
            )
            if shipment.get("out_for_delivery_ts") is not None:
                failed_ts = max(
                    failed_ts,
                    shipment["out_for_delivery_ts"] + timedelta(hours=1),
                )
            failed_ts = _fit_to_operating_window(
                connection,
                failed_ts,
                LAST_MILE_START,
                LAST_MILE_END,
            )

            return_plan = _get_return_plan(
                shipment_id,
                shipment.get("delivery_issue_reason"),
            )
            return_ts = failed_ts + timedelta(
                hours=return_plan["return_delay_hours"]
            )

            if simulation_ts < return_ts:
                continue

            values = {
                "returned_ts": return_ts,
                "shipment_status": "RETURN_TO_SELLER",
                "return_reason": return_plan["return_reason"],
            }
            connection.execute(
                text("""
                    UPDATE core.fact_shipment
                    SET
                        returned_ts = :returned_ts,
                        shipment_status = :shipment_status,
                        return_reason = :return_reason
                    WHERE shipment_id = :shipment_id;
                """),
                {"shipment_id": shipment_id, **values},
            )
            _update_raw_shipment(connection, shipment_id, values)

    return left_dp_count, completed_count


def _pick_weight_kg(rng):
    bucket = rng.random()
    if bucket < 0.70:
        value = rng.uniform(0.20, 3.00)
    elif bucket < 0.95:
        value = rng.uniform(3.00, 10.00)
    else:
        value = rng.uniform(10.00, 30.00)
    return money(value)


def generate_shipments(connection, simulation_ts, batch_no, invoices, rng):
    """Create one shipment per shipping invoice using the final expedition model."""
    if not invoices:
        return 0

    business_date = simulation_ts.date()

    drop_points = connection.execute(
        text("""
            SELECT drop_point_id, area
            FROM core.dim_drop_point
            ORDER BY drop_point_id;
        """)
    ).mappings().all()

    if not drop_points:
        raise RuntimeError("No Drop Point master data found.")

    dp_by_id = {row["drop_point_id"]: row for row in drop_points}
    all_dp_ids = list(dp_by_id)
    shipment_rows = []

    for index, invoice in enumerate(invoices, start=1):
        sla_hours = rng.choice([24, 48, 72])
        origin_dp_id = invoice["origin_dp_id"]

        other_dp_ids = [dp for dp in all_dp_ids if dp != origin_dp_id]
        if not other_dp_ids or rng.random() < LOCAL_DESTINATION_RATE:
            destination_dp_id = origin_dp_id
        else:
            destination_dp_id = rng.choice(other_dp_ids)

        shipment_id = (
            f"SIM-SHP-{business_date:%Y%m%d}"
            f"-B{batch_no:05d}-{index:04d}"
        )

        receiver_area = dp_by_id[destination_dp_id]["area"]
        receiver_name = f"Receiver {shipment_id[-10:]}"

        shipment_rows.append({
            "shipment_id": shipment_id,
            "invoice_id": invoice["invoice_id"],
            "origin_dp_id": origin_dp_id,
            "destination_dp_id": destination_dp_id,
            "seller_id": invoice["seller_id"],
            "receiver_name": receiver_name,
            "receiver_area": receiver_area,
            "courier_id": None,
            "weight_kg": _pick_weight_kg(rng),
            "created_ts": simulation_ts,
            "received_ts": simulation_ts,
            "sorted_ts": None,
            "left_dp_ts": None,
            "arrived_destination_ts": None,
            "out_for_delivery_ts": None,
            "target_delivery_ts": None,
            "actual_delivery_ts": None,
            "returned_ts": None,
            "shipment_status": "RECEIVED",
            "sla_hours": sla_hours,
            "attempt_count": 1,
            "parcel_issue_reason": None,
            "delivery_issue_reason": None,
            "return_reason": None,
        })

    connection.execute(
        text("""
            INSERT INTO core.fact_shipment (
                shipment_id,
                invoice_id,
                origin_dp_id,
                destination_dp_id,
                seller_id,
                receiver_name,
                receiver_area,
                courier_id,
                weight_kg,
                created_ts,
                received_ts,
                sorted_ts,
                left_dp_ts,
                arrived_destination_ts,
                out_for_delivery_ts,
                target_delivery_ts,
                actual_delivery_ts,
                returned_ts,
                shipment_status,
                sla_hours,
                attempt_count,
                parcel_issue_reason,
                delivery_issue_reason,
                return_reason
            )
            VALUES (
                :shipment_id,
                :invoice_id,
                :origin_dp_id,
                :destination_dp_id,
                :seller_id,
                :receiver_name,
                :receiver_area,
                :courier_id,
                :weight_kg,
                :created_ts,
                :received_ts,
                :sorted_ts,
                :left_dp_ts,
                :arrived_destination_ts,
                :out_for_delivery_ts,
                :target_delivery_ts,
                :actual_delivery_ts,
                :returned_ts,
                :shipment_status,
                :sla_hours,
                :attempt_count,
                :parcel_issue_reason,
                :delivery_issue_reason,
                :return_reason
            );
        """),
        shipment_rows,
    )

    raw_rows = [
        {key: raw_value(value) for key, value in row.items()}
        for row in shipment_rows
    ]

    connection.execute(
        text("""
            INSERT INTO raw.fact_shipment (
                shipment_id,
                invoice_id,
                origin_dp_id,
                destination_dp_id,
                seller_id,
                receiver_name,
                receiver_area,
                courier_id,
                weight_kg,
                created_ts,
                received_ts,
                sorted_ts,
                left_dp_ts,
                arrived_destination_ts,
                out_for_delivery_ts,
                target_delivery_ts,
                actual_delivery_ts,
                returned_ts,
                shipment_status,
                sla_hours,
                attempt_count,
                parcel_issue_reason,
                delivery_issue_reason,
                return_reason
            )
            VALUES (
                :shipment_id,
                :invoice_id,
                :origin_dp_id,
                :destination_dp_id,
                :seller_id,
                :receiver_name,
                :receiver_area,
                :courier_id,
                :weight_kg,
                :created_ts,
                :received_ts,
                :sorted_ts,
                :left_dp_ts,
                :arrived_destination_ts,
                :out_for_delivery_ts,
                :target_delivery_ts,
                :actual_delivery_ts,
                :returned_ts,
                :shipment_status,
                :sla_hours,
                :attempt_count,
                :parcel_issue_reason,
                :delivery_issue_reason,
                :return_reason
            );
        """),
        raw_rows,
    )

    return len(shipment_rows)



# ============================================================

# MAIN

# One run = one 5-minute simulated interval.

# ============================================================



def run_simulation():

    with engine.begin() as connection:

        state = connection.execute(

            text("""

                SELECT

                    simulation_name,

                    current_business_date,

                    current_business_time,

                    batch_no,

                    interval_no,

                    simulation_mode,

                    is_enabled

                FROM app.simulation_state

                WHERE simulation_name = :simulation_name

                FOR UPDATE;

            """),

            {"simulation_name": SIMULATION_NAME},

        ).mappings().one()



        if not state["is_enabled"]:

            return {

                "status": "disabled",

                "simulation_name": SIMULATION_NAME,

            }



        next_date, next_time = get_next_simulation_point(

            connection,

            state["current_business_date"],

            state["current_business_time"],

        )



        new_business_day = next_date != state["current_business_date"]

        interval_no = 1 if new_business_day else state["interval_no"] + 1

        batch_no = state["batch_no"] + 1

        simulation_ts = datetime.combine(next_date, next_time)



        seed = int(

            f"{next_date:%Y%m%d}"

            f"{next_time:%H%M}"

            f"{batch_no:05d}"

        )

        rng = random.Random(seed)



        left_dp_rows, completed_rows = advance_shipments(

            connection,

            simulation_ts,

        )



        target_rows = ensure_month_targets(connection, next_date)



        revenue_rows, invoices = generate_revenue_batch(

            connection,

            simulation_ts,

            batch_no,

            rng,

        )



        shipment_rows = generate_shipments(

            connection,

            simulation_ts,

            batch_no,

            invoices,

            rng,

        )



        received_rows = shipment_rows



        connection.execute(

            text("""

                UPDATE app.simulation_state

                SET

                    current_business_date = :business_date,

                    current_business_time = :business_time,

                    batch_no = :batch_no,

                    interval_no = :interval_no,

                    simulation_mode = 'INTRADAY',

                    last_run_at = NOW()

                WHERE simulation_name = :simulation_name;

            """),

            {

                "business_date": next_date,

                "business_time": next_time,

                "batch_no": batch_no,

                "interval_no": interval_no,

                "simulation_name": SIMULATION_NAME,

            },

        )



        connection.execute(

            text("""

                INSERT INTO app.simulation_run_log (

                    simulation_name,

                    business_date,

                    business_time,

                    simulation_ts,

                    batch_no,

                    interval_no,

                    revenue_rows,

                    shipment_rows,

                    received_rows,

                    left_dp_rows,

                    completed_rows,

                    target_rows

                )

                VALUES (

                    :simulation_name,

                    :business_date,

                    :business_time,

                    :simulation_ts,

                    :batch_no,

                    :interval_no,

                    :revenue_rows,

                    :shipment_rows,

                    :received_rows,

                    :left_dp_rows,

                    :completed_rows,

                    :target_rows

                );

            """),

            {

                "simulation_name": SIMULATION_NAME,

                "business_date": next_date,

                "business_time": next_time,

                "simulation_ts": simulation_ts,

                "batch_no": batch_no,

                "interval_no": interval_no,

                "revenue_rows": len(revenue_rows),

                "shipment_rows": shipment_rows,

                "received_rows": received_rows,

                "left_dp_rows": left_dp_rows,

                "completed_rows": completed_rows,

                "target_rows": target_rows,

            },

        )



    return {

        "status": "success",

        "simulation_name": SIMULATION_NAME,

        "simulation_mode": "INTRADAY",

        "business_date": next_date,

        "business_time": next_time,

        "simulation_ts": simulation_ts,

        "interval_no": interval_no,

        "batch_no": batch_no,

        "revenue_rows": len(revenue_rows),

        "invoice_count": len(invoices),

        "shipment_rows": shipment_rows,

        "received_rows": received_rows,

        "left_dp_rows": left_dp_rows,

        "completed_rows": completed_rows,

        "target_rows": target_rows,

    }





if __name__ == "__main__":

    print(json.dumps(run_simulation(), default=str, indent=2))
