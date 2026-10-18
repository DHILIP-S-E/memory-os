"""Google sign-in: link an account to its Google id

Revision ID: 009
Revises: 008
Create Date: 2026-10-18
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "009"
down_revision: Union[str, None] = "008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("users") as batch:
        batch.add_column(sa.Column("google_sub", sa.String(255), nullable=True))
        batch.create_unique_constraint("uq_users_google_sub", ["google_sub"])


def downgrade() -> None:
    with op.batch_alter_table("users") as batch:
        batch.drop_constraint("uq_users_google_sub", type_="unique")
        batch.drop_column("google_sub")
