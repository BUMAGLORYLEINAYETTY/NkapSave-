"""Import all models so SQLAlchemy registers them on Base.metadata."""
from . import user, expense, savings, transaction, njangi, reminder, notification, momo, statement, identity  # noqa: F401
