from app.repositories.operational_repository import (
    get_operational_summary,
    get_drop_points,
    get_drop_point_detail,
    get_drop_point_sellers,
    get_drop_point_parcel,
    get_drop_point_delivery,
    get_drop_point_seller_pics,
    get_drop_point_team,
    get_drop_point_responsibility,
    get_daily_report,
    get_daily_pulse,
    get_parcel_queue,
)


def get_summary():
    rows = get_operational_summary()
    return {"count": len(rows), "data": rows}


def get_all_drop_points():
    rows = get_drop_points()
    return {"count": len(rows), "data": rows}


def get_drop_point(drop_point_id: str):
    return get_drop_point_detail(drop_point_id.upper())


def get_sellers_by_drop_point(drop_point_id: str):
    drop_point_id = drop_point_id.upper()
    if get_drop_point_detail(drop_point_id) is None:
        return None

    rows = get_drop_point_sellers(drop_point_id)
    return {
        "drop_point_id": drop_point_id,
        "count": len(rows),
        "data": rows,
    }


def get_parcels_by_drop_point(drop_point_id: str):
    drop_point_id = drop_point_id.upper()
    if get_drop_point_detail(drop_point_id) is None:
        return None

    result = get_drop_point_parcel(drop_point_id)
    return {
        "drop_point_id": drop_point_id,
        "data": result.get("summary") if isinstance(result, dict) else None,
        "issues": result.get("issues", []) if isinstance(result, dict) else [],
    }


def get_delivery_by_drop_point(drop_point_id: str):
    drop_point_id = drop_point_id.upper()
    if get_drop_point_detail(drop_point_id) is None:
        return None

    result = get_drop_point_delivery(drop_point_id)
    return {
        "drop_point_id": drop_point_id,
        **result,
    }


def get_seller_pics_by_drop_point(drop_point_id: str):
    drop_point_id = drop_point_id.upper()
    if get_drop_point_detail(drop_point_id) is None:
        return None

    rows = get_drop_point_seller_pics(drop_point_id)
    return {
        "drop_point_id": drop_point_id,
        "count": len(rows),
        "data": rows,
    }


def get_team_by_drop_point(drop_point_id: str):
    drop_point_id = drop_point_id.upper()
    if get_drop_point_detail(drop_point_id) is None:
        return None

    rows = get_drop_point_team(drop_point_id)
    manager = next(
        (
            row for row in rows
            if row.get("unit_code") == "MANAGEMENT"
            and row.get("role_code") == "MANAGER"
        ),
        None,
    )
    return {
        "drop_point_id": drop_point_id,
        "manager": manager,
        "count": len(rows),
        "data": rows,
    }


def get_responsibility_by_drop_point(drop_point_id: str):
    drop_point_id = drop_point_id.upper()
    if get_drop_point_detail(drop_point_id) is None:
        return None

    rows = get_drop_point_responsibility(drop_point_id)
    manager = None
    if rows:
        manager = {
            "staff_id": rows[0].get("manager_staff_id"),
            "staff_name": rows[0].get("manager_name"),
        }
    else:
        detail = get_drop_point_detail(drop_point_id) or {}
        manager = {
            "staff_id": detail.get("manager_staff_id"),
            "staff_name": detail.get("manager_name"),
        }

    return {
        "drop_point_id": drop_point_id,
        "manager": manager,
        "count": len(rows),
        "data": rows,
    }


def get_daily_operational_report():
    rows = get_daily_report()
    return {
        "business_date": rows[0]["business_date"] if rows else None,
        "count": len(rows),
        "data": rows,
    }


def get_operational_pulse(drop_point_ids: list[str], days: int = 7):
    rows = get_daily_pulse(drop_point_ids, days)
    return {
        "as_of_date": rows[-1]["business_date"] if rows else None,
        "days": days,
        "count": len(rows),
        "data": rows,
    }


def get_drop_point_parcel_queue(drop_point_id: str):
    rows = get_parcel_queue(drop_point_id)
    return {"drop_point_id": drop_point_id, "count": len(rows), "limit": 100, "data": rows}
