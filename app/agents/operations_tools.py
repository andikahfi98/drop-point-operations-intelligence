from app.services.operational_service import (
    get_summary,
    get_drop_point,
    get_sellers_by_drop_point,
    get_parcels_by_drop_point,
    get_delivery_by_drop_point,
    get_seller_pics_by_drop_point,
    get_team_by_drop_point,
    get_responsibility_by_drop_point,
)


def overall_summary():
    return get_summary()


def drop_point_summary(drop_point_id: str):
    result = get_drop_point(drop_point_id)
    return result if result is not None else {"error": "Drop Point not found"}


def seller_attention(drop_point_id: str):
    result = get_sellers_by_drop_point(drop_point_id)
    return result if result is not None else {"error": "Drop Point not found"}


def parcel_flow(drop_point_id: str):
    result = get_parcels_by_drop_point(drop_point_id)
    return result if result is not None else {"error": "Drop Point not found"}


def delivery_performance(drop_point_id: str):
    result = get_delivery_by_drop_point(drop_point_id)
    return result if result is not None else {"error": "Drop Point not found"}


def seller_pic_performance(drop_point_id: str):
    """Seller-unit PIC performance: Revenue and active Seller coverage only."""
    result = get_seller_pics_by_drop_point(drop_point_id)
    return result if result is not None else {"error": "Drop Point not found"}


def drop_point_team(drop_point_id: str):
    result = get_team_by_drop_point(drop_point_id)
    return result if result is not None else {"error": "Drop Point not found"}


def status_responsibility(drop_point_id: str):
    result = get_responsibility_by_drop_point(drop_point_id)
    return result if result is not None else {"error": "Drop Point not found"}


def diagnose_drop_point(query: str):
    """
    Diagnose one Drop Point using Revenue, Seller, Parcel, Delivery,
    responsibility mapping, and Drop Point team structure.
    Severity is never recalculated here.
    """
    summary = get_summary()
    rows = summary.get("data", []) if isinstance(summary, dict) else []

    normalized_query = str(query).lower().replace("drop point", "").strip()

    selected = None
    for row in rows:
        dp_id = str(row.get("drop_point_id", "")).lower().strip()
        dp_name = (
            str(row.get("drop_point_name", ""))
            .lower()
            .replace("drop point", "")
            .strip()
        )
        if (
            normalized_query == dp_id
            or normalized_query == dp_name
            or (normalized_query and normalized_query in dp_name)
        ):
            selected = row
            break

    if selected is None:
        return {"error": "Drop Point not found"}

    drop_point_id = selected["drop_point_id"]
    sellers = get_sellers_by_drop_point(drop_point_id)
    parcels = get_parcels_by_drop_point(drop_point_id)
    delivery = get_delivery_by_drop_point(drop_point_id)
    seller_pics = get_seller_pics_by_drop_point(drop_point_id)
    team = get_team_by_drop_point(drop_point_id)
    responsibility = get_responsibility_by_drop_point(drop_point_id)

    seller_rows = sellers.get("data", []) if isinstance(sellers, dict) else []
    problem_sellers = [
        row for row in seller_rows
        if row.get("attention_status") in ("CRITICAL", "WATCH")
    ][:5]

    pic_rows = seller_pics.get("data", []) if isinstance(seller_pics, dict) else []
    problem_seller_pics = [
        row for row in pic_rows
        if row.get("pic_status") in ("CRITICAL", "WATCH")
    ][:3]

    return {
        "drop_point": selected,
        "parcel": parcels.get("data") if isinstance(parcels, dict) else None,
        "top_parcel_issues": (
            parcels.get("issues", [])[:5] if isinstance(parcels, dict) else []
        ),
        "delivery": delivery.get("summary") if isinstance(delivery, dict) else None,
        "top_delivery_issues": (
            delivery.get("issues", [])[:5] if isinstance(delivery, dict) else []
        ),
        "top_problem_sellers": problem_sellers,
        "top_problem_seller_pics": problem_seller_pics,
        "responsibility": (
            responsibility.get("data", []) if isinstance(responsibility, dict) else []
        ),
        "manager": (
            responsibility.get("manager") if isinstance(responsibility, dict) else None
        ),
        "team": team.get("data", []) if isinstance(team, dict) else [],
    }
