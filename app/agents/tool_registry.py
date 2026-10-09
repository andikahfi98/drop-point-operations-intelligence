import json

from agents.decorators import tool

from app.agents.operations_tools import (
    overall_summary,
    drop_point_summary,
    seller_attention,
    parcel_flow,
    delivery_performance,
    seller_pic_performance,
    drop_point_team,
    status_responsibility,
    diagnose_drop_point,
)


def as_json(data):
    return json.dumps(data, default=str, ensure_ascii=False)


@tool
def get_overall_summary() -> str:
    """Get current operational summary for all Drop Points."""
    return as_json(overall_summary())


@tool
def get_drop_point_summary(drop_point_id: str) -> str:
    """Get Revenue, Seller, Parcel, Delivery and overall status for one DP."""
    return as_json(drop_point_summary(drop_point_id))


@tool
def get_seller_attention(drop_point_id: str) -> str:
    """Get Seller activity and attention status for one Drop Point."""
    return as_json(seller_attention(drop_point_id))


@tool
def get_parcel_flow(drop_point_id: str) -> str:
    """Get parcel flow, parcel-at-DP, aging and parcel issues for one DP."""
    return as_json(parcel_flow(drop_point_id))


@tool
def get_delivery_performance(drop_point_id: str) -> str:
    """Get last-mile delivery performance and delivery issues for one DP."""
    return as_json(delivery_performance(drop_point_id))


@tool
def get_seller_pic_performance(drop_point_id: str) -> str:
    """Get Seller-unit PIC Revenue and active Seller performance."""
    return as_json(seller_pic_performance(drop_point_id))


@tool
def get_drop_point_team(drop_point_id: str) -> str:
    """Get Drop Point Manager and PIC/staff structure by operational unit."""
    return as_json(drop_point_team(drop_point_id))


@tool
def get_status_responsibility(drop_point_id: str) -> str:
    """Map current WATCH/CRITICAL components to responsible unit, PIC and manager."""
    return as_json(status_responsibility(drop_point_id))


@tool
def diagnose_drop_point_operation(query: str) -> str:
    """
    Diagnose one Drop Point using Revenue, Seller, Parcel, Delivery,
    responsibility and team context. Severity follows analytics output.
    """
    return as_json(diagnose_drop_point(query))
