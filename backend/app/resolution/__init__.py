from app.resolution.normalizers import (
    normalize_doi,
    normalize_pmid,
    normalize_title,
    extract_first_author_surname,
    build_deterministic_key,
)
from app.resolution.similarity import (
    levenshtein_distance,
    token_sort_ratio,
    is_title_match,
)
from app.resolution.merger import (
    calculate_completeness,
    merge_authors,
    merge_canonical_papers,
)
from app.resolution.resolver import IdentityResolver

__all__ = [
    "normalize_doi",
    "normalize_pmid",
    "normalize_title",
    "extract_first_author_surname",
    "build_deterministic_key",
    "levenshtein_distance",
    "token_sort_ratio",
    "is_title_match",
    "calculate_completeness",
    "merge_authors",
    "merge_canonical_papers",
    "IdentityResolver",
]
