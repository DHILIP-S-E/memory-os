"""per-account consent to send captured content to the AI

Revision ID: 010
Revises: 009
Create Date: 2026-10-18

Accounts that already existed keep the behaviour they had (AI on). New accounts are created
with it off by the application and choose for themselves.
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

revision: str = "010"
down_revision: Union[str, None] = "009"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("ai_enabled", sa.Boolean(), nullable=False, server_default=sa.true()))


def downgrade() -> None:
    op.drop_column("users", "ai_enabled")
