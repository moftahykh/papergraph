from typing import Optional
from fastapi import APIRouter, Depends, status
from app.schemas.resolve import PaperResolveRequest, PaperResolveResponse
from app.resolution.resolver import IdentityResolver
from app.providers.semantic_scholar import SemanticScholarProvider
from app.providers.openalex import OpenAlexProvider
from app.core.auth import get_optional_auth_user, AuthenticatedUser

router = APIRouter(tags=["Resolve"])

resolver = IdentityResolver()
s2_provider = SemanticScholarProvider()
openalex_provider = OpenAlexProvider()


@router.post("/papers/resolve", response_model=PaperResolveResponse)
async def resolve_paper_identifier(
    request: PaperResolveRequest,
    auth_user: Optional[AuthenticatedUser] = Depends(get_optional_auth_user),
) -> PaperResolveResponse:
    """
    Resolves any raw academic identifier (bare DOI, DOI URL, PMID, S2 ID, or title)
    into a canonical record. If ambiguous, returns disambiguation candidates.
    """
    raw_id = request.identifier.strip()

    # 1. Try resolving via upstream providers
    raw_paper = None
    try:
        raw_paper = await s2_provider.resolve(raw_id)
        if not raw_paper and openalex_provider:
            raw_paper = await openalex_provider.resolve(raw_id)
    except Exception:
        pass

    if raw_paper:
        canonical = resolver.ingest(raw_paper.to_canonical())
        return PaperResolveResponse(
            resolved=True,
            paper=canonical,
            confidence=1.0,
            message="Resolved via exact provider identifier match.",
        )

    # 2. If free-text title query, search for candidate matches
    try:
        search_results = await s2_provider.search(raw_id, limit=5)
    except Exception:
        search_results = []

    if not search_results:
        return PaperResolveResponse(
            resolved=False,
            paper=None,
            confidence=0.0,
            message="No publications found matching identifier.",
        )

    canonical_candidates = [r.to_canonical() for r in search_results]

    # Check if top candidate is an exact title match
    top_match = canonical_candidates[0]
    if len(canonical_candidates) == 1 or top_match.normalized_title == raw_id.lower().strip():
        canonical = resolver.ingest(top_match)
        return PaperResolveResponse(
            resolved=True,
            paper=canonical,
            confidence=0.95,
            message="Resolved via unambiguous title match.",
        )

    # Ambiguous title with multiple candidates
    return PaperResolveResponse(
        resolved=False,
        paper=None,
        ambiguous_candidates=canonical_candidates[:5],
        confidence=0.65,
        message="Multiple publications matched query. Disambiguation required.",
    )
