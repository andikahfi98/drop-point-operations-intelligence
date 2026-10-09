from sqlalchemy import text

from app.db.database import engine
from app.simulation.simulator import run_simulation


def execute_simulation():
    return run_simulation()


def get_simulation_state():

    query = text("""
    SELECT
        simulation_name,
        simulation_mode,
        current_business_date,
        current_business_time,
        interval_no,
        batch_no,
        is_enabled,
        last_run_at

    FROM app.simulation_state

    WHERE simulation_name =
        'operations_demo';
    """)

    with engine.connect() as connection:
        row = connection.execute(query).mappings().one()

    return dict(row)