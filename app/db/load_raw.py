from pathlib import Path
import os
import re
import sys

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL


BASE_DIR = Path(__file__).resolve().parents[2]
SOURCE_FILE = BASE_DIR / "data" / "raw" / "telegram_reporting_drop_point_dataset_v2.xlsx"
ENV_FILE = BASE_DIR / ".env"
load_dotenv(ENV_FILE)

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "drop_point_ops")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD")

DATABASE_URL = URL.create(
    drivername="postgresql+psycopg",
    username=DB_USER,
    password=DB_PASSWORD,
    host=DB_HOST,
    port=DB_PORT,
    database=DB_NAME,
)
engine = create_engine(DATABASE_URL, pool_pre_ping=True)

# The source workbook keeps its historical sheet names. This loader converts
# those columns into the final expedition/logistics raw-domain terminology.
REQUIRED_SHEETS = [
    "DimDate",
    "DimDropPoint",
    "DimSalesperson",
    "DimOutlet",
    "FactSales",
    "FactDelivery",
    "FactTarget",
    "AppRole",
    "AppUser",
    "UserDropPointAccess",
]

RAW_TABLES = [
    "dim_date",
    "dim_drop_point",
    "dim_staff",
    "dim_seller",
    "fact_revenue",
    "fact_shipment",
    "fact_seller_target",
    "fact_delivery_target",
    "app_role",
    "app_user",
    "user_drop_point_access",
]


def to_snake_case(name: str) -> str:
    name = str(name).strip()
    name = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1_\2", name)
    name = re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name)
    return name.lower()


def validate_source_file() -> None:
    if not SOURCE_FILE.exists():
        print("\nERROR: Excel source file not found:")
        print(SOURCE_FILE)
        sys.exit(1)


def validate_sheets(excel_file: pd.ExcelFile) -> None:
    existing = set(excel_file.sheet_names)
    missing = [sheet for sheet in REQUIRED_SHEETS if sheet not in existing]
    if missing:
        print("\nERROR: Missing Excel sheets:")
        for sheet in missing:
            print(f"  - {sheet}")
        sys.exit(1)


def read_sheet(excel_file: pd.ExcelFile, sheet_name: str) -> pd.DataFrame:
    df = pd.read_excel(excel_file, sheet_name=sheet_name, dtype=str)
    df.columns = [to_snake_case(column) for column in df.columns]
    return df.where(pd.notna(df), None)


def write_raw(connection, table_name: str, df: pd.DataFrame) -> int:
    if df.empty:
        return 0
    df.to_sql(
        name=table_name,
        con=connection,
        schema="raw",
        if_exists="append",
        index=False,
        method="multi",
        chunksize=1000,
    )
    return len(df)


def truncate_raw_tables(connection) -> None:
    tables = [f"raw.{table_name}" for table_name in RAW_TABLES]
    connection.execute(text("TRUNCATE TABLE " + ", ".join(tables) + " RESTART IDENTITY;"))


def normalize_staff(df: pd.DataFrame) -> pd.DataFrame:
    result = df.rename(
        columns={
            "salesperson_id": "staff_id",
            "salesperson_name": "staff_name",
            "role": "role_code",
        }
    ).copy()
    result["unit_code"] = "SELLER"
    result["role_code"] = "PIC"
    result["manager_staff_id"] = result["drop_point_id"].map(
        lambda value: "MGR-" + str(value).replace("DP-", "") if value else None
    )
    for column in ["join_date", "status"]:
        if column not in result.columns:
            result[column] = None
    return result[
        [
            "staff_id", "staff_name", "drop_point_id", "unit_code",
            "role_code", "manager_staff_id", "join_date", "status",
        ]
    ]


def normalize_seller(df: pd.DataFrame) -> pd.DataFrame:
    result = df.rename(
        columns={
            "outlet_id": "seller_id",
            "bp_code": "seller_code",
            "outlet_name": "seller_name",
            "salesperson_id": "seller_pic_id",
            "pic_id": "seller_pic_id",
            "segment": "seller_segment",
        }
    ).copy()
    for column in ["seller_segment", "city_area", "active_flag", "open_date"]:
        if column not in result.columns:
            result[column] = None
    return result[
        [
            "seller_id", "seller_code", "seller_name", "drop_point_id",
            "seller_pic_id", "seller_segment", "city_area", "active_flag", "open_date",
        ]
    ]


def normalize_revenue(df: pd.DataFrame) -> pd.DataFrame:
    result = df.rename(
        columns={
            "salesperson_id": "seller_pic_id",
            "pic_id": "seller_pic_id",
            "outlet_id": "seller_id",
            "date": "revenue_date",
            "net_sales": "revenue",
        }
    ).copy()

    required = [
        "revenue_date", "invoice_id", "drop_point_id",
        "seller_pic_id", "seller_id", "revenue",
    ]
    missing = [column for column in required if column not in result.columns]
    if missing:
        raise ValueError(f"FactSales missing columns: {missing}")

    result["revenue"] = pd.to_numeric(result["revenue"], errors="raise")
    if "transaction_ts" not in result.columns:
        result["transaction_ts"] = result["revenue_date"].astype(str).str[:10] + " 12:00:00"

    grouped = (
        result.groupby("invoice_id", as_index=False)
        .agg(
            revenue_date=("revenue_date", "first"),
            transaction_ts=("transaction_ts", "first"),
            drop_point_id=("drop_point_id", "first"),
            seller_pic_id=("seller_pic_id", "first"),
            seller_id=("seller_id", "first"),
            revenue=("revenue", "sum"),
        )
    )
    grouped["revenue"] = grouped["revenue"].map(lambda value: f"{value:.2f}")
    return grouped[
        [
            "revenue_date", "transaction_ts", "invoice_id", "drop_point_id",
            "seller_pic_id", "seller_id", "revenue",
        ]
    ]


def normalize_shipment(df: pd.DataFrame) -> pd.DataFrame:
    result = df.copy()
    for column in ["shipment_ts", "target_delivery_ts", "actual_delivery_ts"]:
        if column not in result.columns:
            result[column] = None

    if "order_date" in result.columns:
        missing = result["shipment_ts"].isna()
        result.loc[missing, "shipment_ts"] = (
            result.loc[missing, "order_date"].astype(str).str[:10] + " 08:00:00"
        )

    if "planned_delivery_date" in result.columns:
        missing = result["target_delivery_ts"].isna()
        result.loc[missing, "target_delivery_ts"] = (
            result.loc[missing, "planned_delivery_date"].astype(str).str[:10] + " 23:59:59"
        )

    if "actual_delivery_date" in result.columns:
        mask = result["actual_delivery_ts"].isna() & result["actual_delivery_date"].notna()
        result.loc[mask, "actual_delivery_ts"] = (
            result.loc[mask, "actual_delivery_date"].astype(str).str[:10] + " 12:00:00"
        )

    result["origin_dp_id"] = result.get("drop_point_id")
    result["destination_dp_id"] = result.get("drop_point_id")
    result["seller_id"] = result.get("outlet_id")
    result["receiver_name"] = result["shipment_id"].map(lambda x: f"Receiver {str(x)[-6:]}")
    result["receiver_area"] = "LEGACY_SOURCE"
    result["courier_id"] = None
    result["weight_kg"] = "1.00"
    result["created_ts"] = result["shipment_ts"]
    result["received_ts"] = result["shipment_ts"]
    result["sorted_ts"] = None
    result["left_dp_ts"] = result["shipment_ts"]
    result["arrived_destination_ts"] = result["shipment_ts"]
    result["out_for_delivery_ts"] = result["shipment_ts"]
    result["returned_ts"] = None
    result["parcel_issue_reason"] = None
    result["return_reason"] = None

    status_source = result.get("delivery_status")
    if status_source is None:
        result["shipment_status"] = "OUT_FOR_DELIVERY"
    else:
        normalized_status = status_source.astype(str).str.upper()
        result["shipment_status"] = normalized_status.map(
            lambda value: (
                "DELIVERED" if value in {"DELIVERED", "ON_TIME", "LATE"}
                else "FAILED" if value == "FAILED"
                else "OUT_FOR_DELIVERY"
            )
        )

    if "sla_hours" not in result.columns:
        result["sla_hours"] = None
    if "attempt_count" not in result.columns:
        result["attempt_count"] = 1
    result["delivery_issue_reason"] = result.get("failure_reason")

    columns = [
        "shipment_id", "invoice_id", "origin_dp_id", "destination_dp_id", "seller_id",
        "receiver_name", "receiver_area", "courier_id", "weight_kg", "created_ts",
        "received_ts", "sorted_ts", "left_dp_ts", "arrived_destination_ts",
        "out_for_delivery_ts", "target_delivery_ts", "actual_delivery_ts", "returned_ts",
        "shipment_status", "sla_hours", "attempt_count", "parcel_issue_reason",
        "delivery_issue_reason", "return_reason",
    ]
    return result[columns]


def split_targets(df: pd.DataFrame):
    result = df.rename(
        columns={
            "salesperson_id": "staff_id",
            "pic_id": "staff_id",
            "sales_target": "revenue_target",
            "active_outlet_target": "active_seller_target",
        }
    ).copy()

    seller_target = result[
        [
            "month_start", "drop_point_id", "staff_id",
            "revenue_target", "active_seller_target",
        ]
    ].copy()

    sla_unique = (
        result.groupby(["month_start", "drop_point_id"])["delivery_sla_target_pct"]
        .nunique(dropna=False)
    )
    if (sla_unique > 1).any():
        raise ValueError(
            "FactTarget contains different delivery SLA targets within the same Drop Point/month."
        )

    delivery_target = (
        result.groupby(["month_start", "drop_point_id"], as_index=False)
        .agg(delivery_sla_target_pct=("delivery_sla_target_pct", "first"))
    )
    return seller_target, delivery_target


def load_raw_data() -> None:
    print("=" * 70)
    print("DROP POINT OPERATIONS INTELLIGENCE")
    print("EXCEL -> POSTGRESQL RAW LOADER (FINAL LOGISTICS DOMAIN)")
    print("=" * 70)

    validate_source_file()
    excel_file = pd.ExcelFile(SOURCE_FILE, engine="openpyxl")
    validate_sheets(excel_file)

    frames = {
        "dim_date": read_sheet(excel_file, "DimDate"),
        "dim_drop_point": read_sheet(excel_file, "DimDropPoint"),
        "dim_staff": normalize_staff(read_sheet(excel_file, "DimSalesperson")),
        "dim_seller": normalize_seller(read_sheet(excel_file, "DimOutlet")),
        "fact_revenue": normalize_revenue(read_sheet(excel_file, "FactSales")),
        "fact_shipment": normalize_shipment(read_sheet(excel_file, "FactDelivery")),
        "app_role": read_sheet(excel_file, "AppRole"),
        "app_user": read_sheet(excel_file, "AppUser"),
        "user_drop_point_access": read_sheet(excel_file, "UserDropPointAccess"),
    }

    seller_target, delivery_target = split_targets(read_sheet(excel_file, "FactTarget"))
    frames["fact_seller_target"] = seller_target
    frames["fact_delivery_target"] = delivery_target

    total_rows = 0
    with engine.begin() as connection:
        connection.execute(text("SELECT 1"))
        truncate_raw_tables(connection)
        for table_name in RAW_TABLES:
            row_count = write_raw(connection, table_name, frames[table_name])
            print(f"raw.{table_name:<28} {row_count:>8,} rows")
            total_rows += row_count

    print("=" * 70)
    print(f"LOAD COMPLETED - TOTAL ROWS: {total_rows:,}")
    print("=" * 70)


if __name__ == "__main__":
    load_raw_data()
