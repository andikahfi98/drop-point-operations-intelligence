import logging

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text

from app.db.database import engine
from app.api.auth_routes import Principal, allowed_drop_points, dashboard_user, require_drop_point
from app.services.operational_service import (
    get_summary,
    get_all_drop_points,
    get_drop_point,
    get_sellers_by_drop_point,
    get_parcels_by_drop_point,
    get_delivery_by_drop_point,
    get_seller_pics_by_drop_point,
    get_team_by_drop_point,
    get_responsibility_by_drop_point,
    get_daily_operational_report,
    get_operational_pulse,
    get_drop_point_parcel_queue,
)


logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/health")
def health_check():
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        return {"status": "ok", "database": "connected"}
    except Exception:
        logger.exception("Health check failed")
        raise HTTPException(status_code=500, detail="Database connection failed")


@router.get("/api/summary")
def operational_summary(user: Principal = Depends(dashboard_user)):
    try:
        allowed = {row["drop_point_id"] for row in allowed_drop_points(user)}
        data = [row for row in get_summary()["data"] if row["drop_point_id"] in allowed]
        return {"count": len(data), "data": data}
    except Exception:
        logger.exception("Failed to load operational summary")
        raise HTTPException(status_code=500, detail="Failed to load operational summary")


@router.get("/api/operations/pulse")
def operational_pulse(
    days: int = Query(default=7, ge=7, le=14),
    user: Principal = Depends(dashboard_user),
):
    ids = [row["drop_point_id"] for row in allowed_drop_points(user)]
    return get_operational_pulse(ids, days)


@router.get("/api/drop-points/{drop_point_id}/pulse")
def drop_point_pulse(
    drop_point_id: str,
    days: int = Query(default=7, ge=7, le=14),
    user: Principal = Depends(dashboard_user),
):
    requested = require_drop_point(user, drop_point_id)
    return get_operational_pulse([requested], days)


@router.get("/api/drop-points/{drop_point_id}/parcel-queue")
def drop_point_parcel_queue(
    drop_point_id: str,
    user: Principal = Depends(dashboard_user),
):
    requested = require_drop_point(user, drop_point_id)
    return get_drop_point_parcel_queue(requested)


@router.get("/api/drop-points")
def drop_points(user: Principal = Depends(dashboard_user)):
    try:
        allowed = {row["drop_point_id"] for row in allowed_drop_points(user)}
        data = [row for row in get_all_drop_points()["data"] if row["drop_point_id"] in allowed]
        return {"count": len(data), "data": data}
    except Exception:
        logger.exception("Failed to load Drop Points")
        raise HTTPException(status_code=500, detail="Failed to load Drop Points")


@router.get("/api/drop-points/{drop_point_id}")
def drop_point_detail(drop_point_id: str, user: Principal = Depends(dashboard_user)):
    try:
        require_drop_point(user, drop_point_id)
        result = get_drop_point(drop_point_id)
        if result is None:
            raise HTTPException(status_code=404, detail="Drop Point not found")
        return result
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to load Drop Point detail")
        raise HTTPException(status_code=500, detail="Failed to load Drop Point detail")


@router.get("/api/drop-points/{drop_point_id}/sellers")
def drop_point_sellers(drop_point_id: str, user: Principal = Depends(dashboard_user)):
    try:
        require_drop_point(user, drop_point_id)
        result = get_sellers_by_drop_point(drop_point_id)
        if result is None:
            raise HTTPException(status_code=404, detail="Drop Point not found")
        return result
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to load seller data")
        raise HTTPException(status_code=500, detail="Failed to load seller data")


@router.get("/api/drop-points/{drop_point_id}/parcels")
def drop_point_parcels(drop_point_id: str, user: Principal = Depends(dashboard_user)):
    try:
        require_drop_point(user, drop_point_id)
        result = get_parcels_by_drop_point(drop_point_id)
        if result is None:
            raise HTTPException(status_code=404, detail="Drop Point not found")
        return result
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to load parcel flow data")
        raise HTTPException(status_code=500, detail="Failed to load parcel flow data")


@router.get("/api/drop-points/{drop_point_id}/delivery")
def drop_point_delivery(drop_point_id: str, user: Principal = Depends(dashboard_user)):
    try:
        require_drop_point(user, drop_point_id)
        result = get_delivery_by_drop_point(drop_point_id)
        if result is None:
            raise HTTPException(status_code=404, detail="Drop Point not found")
        return result
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to load delivery data")
        raise HTTPException(status_code=500, detail="Failed to load delivery data")


@router.get("/api/drop-points/{drop_point_id}/seller-pics")
def drop_point_seller_pics(drop_point_id: str, user: Principal = Depends(dashboard_user)):
    try:
        require_drop_point(user, drop_point_id)
        result = get_seller_pics_by_drop_point(drop_point_id)
        if result is None:
            raise HTTPException(status_code=404, detail="Drop Point not found")
        return result
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to load Seller PIC performance")
        raise HTTPException(status_code=500, detail="Failed to load Seller PIC performance")


@router.get("/api/drop-points/{drop_point_id}/team")
def drop_point_team(drop_point_id: str, user: Principal = Depends(dashboard_user)):
    try:
        require_drop_point(user, drop_point_id)
        result = get_team_by_drop_point(drop_point_id)
        if result is None:
            raise HTTPException(status_code=404, detail="Drop Point not found")
        return result
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to load Drop Point team")
        raise HTTPException(status_code=500, detail="Failed to load Drop Point team")


@router.get("/api/drop-points/{drop_point_id}/responsibility")
def drop_point_responsibility(drop_point_id: str, user: Principal = Depends(dashboard_user)):
    try:
        require_drop_point(user, drop_point_id)
        result = get_responsibility_by_drop_point(drop_point_id)
        if result is None:
            raise HTTPException(status_code=404, detail="Drop Point not found")
        return result
    except HTTPException:
        raise
    except Exception:
        logger.exception("Failed to load responsibility mapping")
        raise HTTPException(status_code=500, detail="Failed to load responsibility mapping")


@router.get("/api/reports/daily")
def daily_operational_report(user: Principal = Depends(dashboard_user)):
    try:
        allowed = {row["drop_point_id"] for row in allowed_drop_points(user)}
        result = get_daily_operational_report()
        data = [row for row in result["data"] if row["drop_point_id"] in allowed]
        return {"business_date": result["business_date"], "count": len(data), "data": data}
    except Exception:
        logger.exception("Failed to load daily report")
        raise HTTPException(status_code=500, detail="Failed to load daily report")
