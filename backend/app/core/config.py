from typing import List, Union, Optional
from pydantic import AnyHttpUrl
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    PROJECT_NAME: str = "PaperGraph Backend"
    VERSION: str = "0.1.0"
    API_V1_STR: str = "/api/v1"

    # Database Settings
    POSTGRES_SERVER: str = "localhost"
    POSTGRES_PORT: int = 5432
    POSTGRES_USER: str = "papergraph"
    POSTGRES_PASSWORD: str = "papergraph_dev_pass"
    POSTGRES_DB: str = "papergraph"

    @property
    def SQLALCHEMY_DATABASE_URI(self) -> str:
        return f"postgresql+asyncpg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}@{self.POSTGRES_SERVER}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"

    # Redis Settings
    REDIS_HOST: str = "localhost"
    REDIS_PORT: int = 6379

    # Academic Provider Configuration
    SEMANTIC_SCHOLAR_API_KEY: Optional[str] = None
    SEMANTIC_SCHOLAR_RPS: float = 1.0

    CROSSREF_MAILTO: str = "developer@example.com"
    CROSSREF_RPS: float = 5.0

    OPENALEX_MAILTO: str = "developer@example.com"
    OPENALEX_RPS: float = 10.0

    NCBI_API_KEY: Optional[str] = None
    PUBMED_RPS: float = 3.0

    PROVIDER_TIMEOUT_SECONDS: float = 10.0
    PROVIDER_MAX_RETRIES: int = 3
    RUN_LIVE_PROVIDER_TESTS: bool = False

    # CORS
    BACKEND_CORS_ORIGINS: List[str] = [
        "http://localhost",
        "http://localhost:3000",
        "http://localhost:8000",
    ]

    # Enrichment Pipeline Settings
    ENRICHMENT_CACHE_TTL: int = 86400  # 24 hours
    ENRICHMENT_MAX_CANDIDATES_REFERENCES: int = 60
    ENRICHMENT_MAX_CANDIDATES_CITATIONS: int = 30
    ENRICHMENT_MAX_REFERENCES_PER_PAPER: int = 200
    ENRICHMENT_MAX_CITATIONS_PER_PAPER: int = 200
    ENRICHMENT_EPSILON: float = 1e-8


settings = Settings()
