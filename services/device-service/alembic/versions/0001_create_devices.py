"""Create devices table.

Revision ID: 0001_create_devices
Revises:
"""

from alembic import op
import sqlalchemy as sa

revision = "0001_create_devices"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "devices",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("hostname", sa.String(length=255), nullable=False),
        sa.Column("management_ip", sa.String(length=45), nullable=False),
        sa.Column("vendor", sa.String(length=32), nullable=False),
        sa.Column("model", sa.String(length=255), nullable=False),
        sa.Column("site", sa.String(length=255), nullable=False),
        sa.Column("software_version", sa.String(length=128), nullable=True),
        sa.Column(
            "status",
            sa.String(length=32),
            nullable=False,
            server_default="unknown",
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("CURRENT_TIMESTAMP"),
        ),
        sa.CheckConstraint(
            "vendor IN ('nokia','cisco','juniper','huawei','arista','other')",
            name="ck_devices_vendor",
        ),
        sa.CheckConstraint(
            "status IN ('active','inactive','maintenance','unreachable','unknown')",
            name="ck_devices_status",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_devices"),
        sa.UniqueConstraint("hostname", name="uq_devices_hostname"),
        sa.UniqueConstraint("management_ip", name="uq_devices_management_ip"),
    )
    op.create_index("ix_devices_hostname", "devices", ["hostname"])
    op.create_index("ix_devices_management_ip", "devices", ["management_ip"])
    op.create_index("ix_devices_site", "devices", ["site"])
    op.create_index("ix_devices_status", "devices", ["status"])


def downgrade() -> None:
    op.drop_index("ix_devices_status", table_name="devices")
    op.drop_index("ix_devices_site", table_name="devices")
    op.drop_index("ix_devices_management_ip", table_name="devices")
    op.drop_index("ix_devices_hostname", table_name="devices")
    op.drop_table("devices")
