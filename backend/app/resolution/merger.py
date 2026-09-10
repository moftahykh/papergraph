from typing import List, Dict, Any, Optional
from datetime import datetime, timezone
from app.models.canonical_paper import CanonicalPaper, Author, SourceAvailability
from app.resolution.normalizers import normalize_doi, normalize_pmid, normalize_title


def calculate_completeness(paper: CanonicalPaper) -> float:
    """Calculates field-level completeness score in [0.0, 1.0]."""
    score = 0.0
    if paper.title and paper.title != "Untitled Work":
        score += 0.20
    if paper.authors:
        score += 0.20
    if paper.year:
        score += 0.15
    if paper.abstract:
        score += 0.20
    if paper.doi:
        score += 0.10
    if paper.venue:
        score += 0.05
    if paper.topics:
        score += 0.05
    if paper.reference_ids:
        score += 0.05
    return min(1.0, round(score, 2))


def merge_authors(existing: List[Author], incoming: List[Author]) -> List[Author]:
    """
    Merges author lists, picking the more complete list while enriching affiliations and IDs.
    Guarantees no authors are dropped if incoming provides a more detailed author list.
    """
    if not existing:
        return incoming
    if not incoming:
        return existing

    # Use the larger author list as the base to avoid dropping co-authors
    if len(incoming) > len(existing):
        base, augment = incoming, existing
    else:
        base, augment = existing, incoming

    augment_map = {a.name.lower().strip(): a for a in augment}
    merged: List[Author] = []

    for a in base:
        key = a.name.lower().strip()
        affil = a.affiliation
        author_id = a.id
        if key in augment_map:
            aug = augment_map[key]
            if not affil and aug.affiliation:
                affil = aug.affiliation
            if not author_id and aug.id:
                author_id = aug.id
        merged.append(
            Author(
                id=author_id,
                name=a.name,
                position=a.position or (len(merged) + 1),
                affiliation=affil,
            )
        )
    return merged


def merge_canonical_papers(
    primary: CanonicalPaper,
    secondary: CanonicalPaper,
) -> CanonicalPaper:
    """
    Merges secondary record into primary record without overwriting better existing values with nulls.
    Preserves and updates cross-provider provenance and data completeness.
    """
    # 1. Identifiers
    doi = primary.doi or secondary.doi
    pmid = primary.pmid or secondary.pmid
    s2_id = primary.semantic_scholar_id or secondary.semantic_scholar_id
    oa_id = primary.open_alex_id or secondary.open_alex_id

    # Canonical ID determination: DOI takes absolute precedence
    if doi:
        canonical_id = f"doi:{normalize_doi(doi)}"
    elif pmid:
        canonical_id = f"pmid:{normalize_pmid(pmid)}"
    elif primary.canonical_id.startswith("doi:") or primary.canonical_id.startswith("pmid:"):
        canonical_id = primary.canonical_id
    elif secondary.canonical_id.startswith("doi:") or secondary.canonical_id.startswith("pmid:"):
        canonical_id = secondary.canonical_id
    else:
        canonical_id = primary.canonical_id

    # 2. Title
    title = primary.title
    if (not title or title == "Untitled Work") and secondary.title:
        title = secondary.title
    elif secondary.title and len(secondary.title) > len(primary.title) and primary.title in secondary.title:
        title = secondary.title
    norm_title = primary.normalized_title or secondary.normalized_title or normalize_title(title)

    # 3. Authors
    authors = merge_authors(primary.authors, secondary.authors)

    # 4. Publication Year & Venue
    year = primary.year if primary.year is not None else secondary.year
    venue = primary.venue if primary.venue else secondary.venue

    # 5. Abstract: Never overwrite existing abstract with null; prefer longer detailed abstract
    abstract = primary.abstract
    if not abstract and secondary.abstract:
        abstract = secondary.abstract
    elif primary.abstract and secondary.abstract:
        if len(secondary.abstract) > len(primary.abstract):
            abstract = secondary.abstract

    # 6. Citations & References
    citation_count = max(primary.citation_count, secondary.citation_count)
    reference_count = max(
        primary.reference_count or 0, secondary.reference_count or 0
    )

    # Deduplicated reference & citation IDs
    ref_set = set(primary.reference_ids)
    for r in secondary.reference_ids:
        if r not in ref_set:
            ref_set.add(r)
    reference_ids = list(ref_set)

    cite_set = set(primary.citation_ids)
    for c in secondary.citation_ids:
        if c not in cite_set:
            cite_set.add(c)
    citation_ids = list(cite_set)

    # 7. Topics
    topic_map = {t.lower(): t for t in primary.topics}
    for t in secondary.topics:
        if t.lower() not in topic_map:
            topic_map[t.lower()] = t
    topics = list(topic_map.values())

    # 8. Source Availability
    sources = SourceAvailability(
        semantic_scholar=(
            primary.source_availability.semantic_scholar
            or secondary.source_availability.semantic_scholar
        ),
        open_alex=(
            primary.source_availability.open_alex
            or secondary.source_availability.open_alex
        ),
        crossref=(
            primary.source_availability.crossref
            or secondary.source_availability.crossref
        ),
        pubmed=(
            primary.source_availability.pubmed
            or secondary.source_availability.pubmed
        ),
    )

    # 9. Provenance Tracking
    provenance = dict(primary.provenance)
    merged_sources = provenance.get("contributors", [])
    if not merged_sources:
        if "primary_provider" in primary.provenance:
            merged_sources.append(primary.provenance["primary_provider"])
    
    sec_provider = secondary.provenance.get("primary_provider")
    if sec_provider and sec_provider not in merged_sources:
        merged_sources.append(sec_provider)
    
    provenance["contributors"] = merged_sources
    provenance["last_merged_at"] = datetime.now(timezone.utc).isoformat()

    merged_paper = CanonicalPaper(
        canonical_id=canonical_id,
        doi=doi,
        pmid=pmid,
        semantic_scholar_id=s2_id,
        open_alex_id=oa_id,
        title=title,
        normalized_title=norm_title,
        authors=authors,
        year=year,
        venue=venue,
        abstract=abstract,
        citation_count=citation_count,
        reference_count=reference_count,
        reference_ids=reference_ids,
        citation_ids=citation_ids,
        topics=topics,
        source_availability=sources,
        provenance=provenance,
        completeness=0.0,
    )
    merged_paper.completeness = calculate_completeness(merged_paper)
    return merged_paper
