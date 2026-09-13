import logging
from typing import Optional
from fastapi import APIRouter, Depends, status
from app.schemas.resolve import PaperResolveRequest, PaperResolveResponse
from app.resolution.resolver import IdentityResolver
from app.resolution.normalizers import classify_identifier
from app.providers.semantic_scholar import SemanticScholarProvider
from app.providers.openalex import OpenAlexProvider
from app.core.auth import get_optional_auth_user, AuthenticatedUser

logger = logging.getLogger("papergraph.api.resolve")

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

    # 1. Try resolving via upstream providers — each isolated in its own
    #    try/except so one provider's failure never skips the other.
    raw_paper = None
    try:
        raw_paper = await s2_provider.resolve(raw_id)
    except Exception as e:
        logger.warning(f"Resolve via semantic_scholar failed: {e}")
    if not raw_paper and openalex_provider:
        try:
            raw_paper = await openalex_provider.resolve(raw_id)
        except Exception as e:
            logger.warning(f"Resolve via openalex failed: {e}")

    # 1b. Universal fallback chain for links/IDs the providers did not resolve
    # directly. NCBI's ID converter first (deterministic for PMCID/PMID),
    # then landing-page citation_* meta-tag scraping for any http(s) link.
    if not raw_paper:
        kind, value = classify_identifier(raw_id)
        if kind in ("pmcid", "pmid"):
            try:
                from app.resolution.link_resolver import resolve_ncbi_idconv

                mapped_id = await resolve_ncbi_idconv(kind, value)
            except Exception:
                mapped_id = None
            if mapped_id:
                try:
                    raw_paper = await s2_provider.resolve(mapped_id)
                except Exception:
                    raw_paper = None
                if not raw_paper and openalex_provider:
                    try:
                        raw_paper = await openalex_provider.resolve(mapped_id)
                    except Exception:
                        raw_paper = None

    # 1c. Any http(s) link the providers couldn't resolve directly: scrape the
    # landing page's citation_* meta tags once, then retry the provider chain.
    # Covers unknown publishers (IEEE, ScienceDirect...) AND known-ID pages
    # (PMC/PubMed/arXiv) whose IDs providers haven't indexed yet.
    if not raw_paper and raw_id.lower().startswith(("http://", "https://")):
        try:
            from app.resolution.link_resolver import resolve_url_to_identifier

            extracted = await resolve_url_to_identifier(raw_id)
        except Exception:
            extracted = None
        if extracted:
            try:
                raw_paper = await s2_provider.resolve(extracted[1])
            except Exception:
                raw_paper = None
            if not raw_paper and openalex_provider:
                try:
                    raw_paper = await openalex_provider.resolve(extracted[1])
                except Exception:
                    raw_paper = None

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
