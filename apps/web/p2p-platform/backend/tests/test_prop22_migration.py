"""TDD: verify Prop 22 migration schema and seed data.

These tests confirm that:
1. ride_requests has 5 new prop22_* columns
2. orders has 5 new prop22_* columns
3. prop22_config has the 2026 CA seed row (multiplier=1.20, mile_rate=0.37)
4. prop22_city_wages has 5 seed rows (CA + SF x2 + LA x2)
5. prop22_earning_periods has the uq_prop22_period_driver_start unique constraint
6. All 4 new ORM classes are importable from models.py

Requires a live database with the migration applied (alembic upgrade head).
"""
import pytest
from sqlalchemy import text
from database import SessionLocal, engine

pytestmark = pytest.mark.skipif(
    engine.dialect.name != "postgresql",
    reason="Needs a Postgres DB with `alembic upgrade head` applied (uses information_schema)",
)


def test_ride_requests_prop22_columns():
    db = SessionLocal()
    try:
        result = db.execute(text("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'ride_requests'
            AND column_name LIKE 'prop22_%'
            ORDER BY column_name
        """)).fetchall()
        cols = [r[0] for r in result]
        assert "prop22_acceptance_lat" in cols
        assert "prop22_acceptance_lon" in cols
        assert "prop22_engaged_hours" in cols
        assert "prop22_engaged_miles" in cols
        assert "prop22_floor_amount" in cols
    finally:
        db.close()


def test_orders_prop22_columns():
    db = SessionLocal()
    try:
        result = db.execute(text("""
            SELECT column_name FROM information_schema.columns
            WHERE table_name = 'orders'
            AND column_name LIKE 'prop22_%'
            ORDER BY column_name
        """)).fetchall()
        cols = [r[0] for r in result]
        assert "prop22_acceptance_lat" in cols
        assert "prop22_acceptance_lon" in cols
        assert "prop22_engaged_hours" in cols
        assert "prop22_engaged_miles" in cols
        assert "prop22_floor_amount" in cols
    finally:
        db.close()


def test_prop22_config_seed():
    db = SessionLocal()
    try:
        result = db.execute(text(
            "SELECT min_wage_multiplier, mile_rate FROM prop22_config WHERE state='CA'"
        )).fetchone()
        assert result is not None, "CA row missing from prop22_config"
        assert result[0] == 1.20
        assert result[1] == 0.37
    finally:
        db.close()


def test_prop22_city_wages_seed():
    db = SessionLocal()
    try:
        result = db.execute(text(
            "SELECT COUNT(*) FROM prop22_city_wages"
        )).scalar()
        assert result == 5, f"Expected 5 seed rows, got {result}"
        sf_rows = db.execute(text(
            "SELECT min_wage FROM prop22_city_wages WHERE city='SAN_FRANCISCO' ORDER BY effective_date"
        )).fetchall()
        assert len(sf_rows) == 2
        assert sf_rows[0][0] == 18.67
        assert sf_rows[1][0] == 19.61
    finally:
        db.close()


def test_prop22_earning_periods_unique_constraint():
    db = SessionLocal()
    try:
        result = db.execute(text("""
            SELECT constraint_name FROM information_schema.table_constraints
            WHERE table_name = 'prop22_earning_periods'
            AND constraint_name = 'uq_prop22_period_driver_start'
        """)).fetchone()
        assert result is not None, "UniqueConstraint uq_prop22_period_driver_start missing"
    finally:
        db.close()


def test_orm_classes_importable():
    from models import (
        Prop22Config, Prop22CityWage,
        Prop22EarningPeriod, Prop22EarningsStatement
    )
    assert Prop22Config.__tablename__ == "prop22_config"
    assert Prop22CityWage.__tablename__ == "prop22_city_wages"
    assert Prop22EarningPeriod.__tablename__ == "prop22_earning_periods"
    assert Prop22EarningsStatement.__tablename__ == "prop22_earnings_statement"
