from typing import Optional, List
from fastapi import APIRouter, Depends
from app.models.canonical_paper import CanonicalPaper
from app.schemas.paper_details import PaperDetailsResponse
from app.providers.semantic_scholar import SemanticScholarProvider
from app.providers.openalex import OpenAlexProvider
from app.resolution.resolver import IdentityResolver
from app.core.errors import NotFoundError
from app.core.auth import get_optional_auth_user, AuthenticatedUser

from app.workers.job_manager import GraphJobManager

router = APIRouter(tags=["Papers"])


def generate_bibtex(paper: CanonicalPaper) -> str:
    """Generates formatted BibTeX citation for a canonical paper."""
    first_author = paper.authors[0].name.split()[-1].lower() if paper.authors else "anon"
    year_str = str(paper.year) if paper.year else "nodate"
    tag = f"{first_author}{year_str}"
    authors_formatted = " and ".join(a.name for a in paper.authors) if paper.authors else "Anonymous"
    
    lines = [
        f"@article{{{tag},",
        f"  title={{{paper.title}}},",
        f"  author={{{authors_formatted}}},",
    ]
    if paper.venue:
        lines.append(f"  journal={{{paper.venue}}},")
    if paper.year:
        lines.append(f"  year={{{paper.year}}},")
    if paper.doi:
        lines.append(f"  doi={{{paper.doi}}},")
    lines.append("}")
    return "\n".join(lines)


@router.get("/papers/{paper_id:path}/details", response_model=PaperDetailsResponse)
async def get_paper_details(
    paper_id: str,
    auth_user: Optional[AuthenticatedUser] = Depends(get_optional_auth_user),
) -> PaperDetailsResponse:
    """
    Retrieves deep on-demand paper metadata (BibTeX, TLDR summary, open-access link)
    when a researcher selects a specific paper in the client.
    """
    clean_id = paper_id.strip()
    manager = GraphJobManager.get_instance()
    resolver = manager.resolver
    s2_provider = manager.s2_provider
    openalex_provider = manager.openalex_provider

    # 1. Check if paper already exists in resolver memory / cache
    canonical = resolver.get_by_id(clean_id)
    if not canonical:
        match_res, _, _ = resolver.find_match(
            CanonicalPaper(
                canonical_id=clean_id,
                doi=clean_id.replace("doi:", "") if "10." in clean_id else None,
                title="Unknown",
            )
        )
        canonical = match_res

    # 2. If paper is not found in memory OR has no abstract, query upstream providers
    #    (S2 and OpenAlex) to enrich with full abstract and deep metadata.
    if not canonical or not canonical.abstract:
        raw = None
        try:
            raw = await s2_provider.resolve(clean_id)
        except Exception:
            raw = None
        if (not raw or not getattr(raw, "abstract", None)) and openalex_provider:
            try:
                raw_oa = await openalex_provider.resolve(clean_id)
                if raw_oa and getattr(raw_oa, "abstract", None):
                    raw = raw_oa
            except Exception:
                pass

        if raw:
            new_canonical = raw.to_canonical()
            if canonical:
                if new_canonical.abstract:
                    canonical.abstract = new_canonical.abstract
                if new_canonical.authors and len(new_canonical.authors) > len(canonical.authors):
                    canonical.authors = new_canonical.authors
                if new_canonical.venue and not canonical.venue:
                    canonical.venue = new_canonical.venue
            else:
                canonical = resolver.ingest(new_canonical)

    if not canonical:
        raise NotFoundError(f"Paper with identifier '{clean_id}' not found.")

    # Extract affiliations
    affiliations: List[str] = []
    for a in canonical.authors:
        if a.affiliation and a.affiliation not in affiliations:
            affiliations.append(a.affiliation)

    # TLDR summary placeholder or extraction from abstract
    tldr = None
    if canonical.abstract:
        first_sentence = canonical.abstract.split(". ")[0]
        tldr = first_sentence + "." if not first_sentence.endswith(".") else first_sentence

    # Direct Open Access URL
    open_access_url = None
    if canonical.doi:
        open_access_url = f"https://doi.org/{canonical.doi}"

    bibtex = generate_bibtex(canonical)

    return PaperDetailsResponse(
        paper=canonical,
        tldr=tldr,
        open_access_url=open_access_url,
        bibtex=bibtex,
        affiliations=affiliations,
        is_saved=False,
    )
