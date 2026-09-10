from typing import Optional, List
from fastapi import APIRouter, Query, Depends
from app.schemas.search import SearchResponse, SearchResultItem
from app.providers.semantic_scholar import SemanticScholarProvider
from app.providers.openalex import OpenAlexProvider
from app.resolution.normalizers import normalize_title
from app.core.auth import get_optional_auth_user, AuthenticatedUser

router = APIRouter(tags=["Search"])

s2_provider = SemanticScholarProvider()
openalex_provider = OpenAlexProvider()


@router.get("/search", response_model=SearchResponse)
async def search_literature(
    query: str = Query(..., min_length=2, max_length=500, description="Search keywords, paper title, or topic."),
    limit: int = Query(default=10, ge=1, le=50, description="Results per page."),
    offset: int = Query(default=0, ge=0, description="Pagination offset."),
    provider: Optional[str] = Query(default=None, description="Optional provider filter."),
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

    # 2. Deduplicate and format results
    seen_ids = set()
    items: List[SearchResultItem] = []

    for r in raw_results:
        cid = r.doi or r.semantic_scholar_id or r.provider_id
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
            score=round(1.0 - (len(items) * 0.05), 2),
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
