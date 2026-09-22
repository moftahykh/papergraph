import re
from typing import Optional, List, Tuple
from fastapi import APIRouter, Query, Depends
from app.schemas.search import SearchResponse, SearchResultItem
from app.providers.semantic_scholar import SemanticScholarProvider
from app.providers.openalex import OpenAlexProvider
from app.providers.models import RawPaper
from app.resolution.normalizers import normalize_title
from app.core.auth import get_optional_auth_user, AuthenticatedUser

router = APIRouter(tags=["Search"])

s2_provider = SemanticScholarProvider()
openalex_provider = OpenAlexProvider()
VALID_SCOPES = {"all", "title", "author"}


def _query_tokens(value: str) -> List[str]:
    """Return meaningful normalized tokens for local, explainable ranking."""
    return [
        token
        for token in re.findall(r"\w+", normalize_title(value), flags=re.UNICODE)
        if len(token) > 1
    ]


def _field_match(query: str, value: str) -> float:
    """Score query coverage in one metadata field without external calls."""
    query_norm = normalize_title(query)
    value_norm = normalize_title(value)
    if not query_norm or not value_norm:
        return 0.0
    if query_norm == value_norm:
        return 1.0
    if query_norm in value_norm:
        return 0.92

    tokens = _query_tokens(query)
    if not tokens:
        return 0.0
    value_tokens = set(_query_tokens(value))
    coverage = sum(token in value_tokens for token in tokens) / len(tokens)
    return round(coverage, 4)


def _rank_raw_paper(
    paper: RawPaper,
    query: str,
    scope: str,
    provider_position: int,
) -> Tuple[float, List[str], str]:
    """Rank one provider result and explain the fields that matched."""
    author_text = " ".join(author.name for author in paper.authors)
    title_score = _field_match(query, paper.title)
    author_score = _field_match(query, author_text)
    abstract_score = _field_match(query, paper.abstract or "")
    topic_score = _field_match(query, " ".join(paper.topics))
    venue_score = _field_match(query, paper.venue or "")

    provider_tiebreak = max(0.0, 1.0 - provider_position * 0.01)
    if scope == "title":
        score = title_score * 0.90 + provider_tiebreak * 0.10
    elif scope == "author":
        score = author_score * 0.90 + provider_tiebreak * 0.10
    else:
        content_score = max(abstract_score, topic_score, venue_score)
        score = (
            title_score * 0.55
            + author_score * 0.25
            + content_score * 0.15
            + provider_tiebreak * 0.05
        )

    matched_fields: List[str] = []
    if title_score >= 0.25:
        matched_fields.append("title")
    if author_score >= 0.25:
        matched_fields.append("author")
    if abstract_score >= 0.25:
        matched_fields.append("abstract")
    if topic_score >= 0.25:
        matched_fields.append("topic")
    if venue_score >= 0.25:
        matched_fields.append("venue")

    labels = {
        "title": "title",
        "author": "author",
        "abstract": "abstract",
        "topic": "topic",
        "venue": "venue",
    }
    if matched_fields:
        readable = [labels[field] for field in matched_fields]
        if len(readable) == 1:
            reason = f"Matched by {readable[0]}"
        elif len(readable) == 2:
            reason = f"Matched by {readable[0]} and {readable[1]}"
        else:
            reason = "Matched by " + ", ".join(readable[:-1]) + f", and {readable[-1]}"
    else:
        reason = "Ranked by provider relevance"

    return round(score, 4), matched_fields, reason


@router.get("/search", response_model=SearchResponse)
async def search_literature(
    query: str = Query(..., min_length=2, max_length=500, description="Search keywords, paper title, or topic."),
    limit: int = Query(default=10, ge=1, le=50, description="Results per page."),
    offset: int = Query(default=0, ge=0, description="Pagination offset."),
    provider: Optional[str] = Query(default=None, description="Optional provider filter."),
    scope: str = Query(
        default="all",
        pattern="^(all|title|author)$",
        description="Local ranking scope: all, title, or author.",
    ),
    auth_user: Optional[AuthenticatedUser] = Depends(get_optional_auth_user),
) -> SearchResponse:
    """
    Performs multi-source academic discovery search with deduplication,
    ranking, and ambiguous title detection.
    """
    raw_results = []
    
    # 1. Search primary provider
    try:
        if provider == "openalex":
            raw_results = await openalex_provider.search(query, limit=limit + 5)
        else:
            raw_results = await s2_provider.search(query, limit=limit + 5)
            if not raw_results and openalex_provider:
                raw_results = await openalex_provider.search(query, limit=limit + 5)
    except Exception:
        # Fallback to OpenAlex if S2 fails
        if openalex_provider and provider != "openalex":
            try:
                raw_results = await openalex_provider.search(query, limit=limit)
            except Exception:
                raw_results = []

    # 2. Rank locally after provider retrieval. This does not add provider
    # requests, and keeps the rate-limit behavior unchanged.
    ranked_results = [
        (
            _rank_raw_paper(raw, query, scope, position),
            raw,
        )
        for position, raw in enumerate(raw_results)
    ]
    ranked_results.sort(key=lambda item: item[0][0], reverse=True)

    # 2. Deduplicate and format results
    seen_ids = set()
    items: List[SearchResultItem] = []

    for (score, matched_fields, match_reason), r in ranked_results:
        cid = (r.doi or r.semantic_scholar_id or r.provider_id).lower()
        if not cid or cid in seen_ids:
            continue
        seen_ids.add(cid)

        author_names = [a.name for a in r.authors[:4]] if r.authors else []
        item = SearchResultItem(
            canonical_id=f"doi:{r.doi}" if r.doi else f"s2:{r.provider_id}",
            title=r.title,
            authors=author_names,
            year=r.year,
            venue=r.venue,
            citation_count=r.citation_count,
            doi=r.doi,
            score=score,
            matched_fields=matched_fields,
            match_reason=match_reason,
        )
        items.append(item)
        if len(items) >= limit:
            break

    # 3. Check for ambiguity (e.g. multiple papers sharing identical normalized title)
    norm_q = normalize_title(query)
    matching_titles = [it for it in items if normalize_title(it.title) == norm_q]
    disambiguation_needed = len(matching_titles) > 1

    return SearchResponse(
        query=query,
        total=len(items),
        items=items,
        disambiguation_needed=disambiguation_needed,
        candidates=matching_titles if disambiguation_needed else [],
    )
