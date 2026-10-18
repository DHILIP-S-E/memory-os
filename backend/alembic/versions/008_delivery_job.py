"""link each delivery attempt to its job (device_id already exists from 001)

Revision ID: 008
Revises: 007
Create Date: 2026-10-18
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "008"
down_revision: Union[str, None] = "007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("notification_deliveries", sa.Column("job_id", sa.String(36), nullable=True))
    op.create_index("ix_notification_deliveries_job_id", "notification_deliveries", ["job_id"])


def downgrade() -> None:
    op.drop_index("ix_notification_deliveries_job_id", table_name="notification_deliveries")
    op.drop_column("notification_deliveries", "job_id")
