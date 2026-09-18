from app.core.config import normalize_database_url


def test_normalize_render_postgres_url_and_ssl():
    source = (
        "postgresql://papergraph:secret@example.render.com:5432/"
        "papergraph?sslmode=require"
    )

    assert normalize_database_url(source) == (
        "postgresql+asyncpg://papergraph:secret@example.render.com:5432/"
        "papergraph?ssl=require"
    )


def test_normalize_postgres_scheme_without_query():
    source = "postgres://papergraph:secret@localhost:5432/papergraph"

    assert normalize_database_url(source) == (
        "postgresql+asyncpg://papergraph:secret@localhost:5432/papergraph"
    )


def test_existing_ssl_parameter_is_preserved():
    source = "postgresql://user:pass@host:5432/db?ssl=require&connect_timeout=5"

    assert normalize_database_url(source) == (
        "postgresql+asyncpg://user:pass@host:5432/db"
        "?ssl=require&connect_timeout=5"
    )