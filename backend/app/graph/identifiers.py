"""Identifier aliases used when joining provider relationship data to graph nodes."""

from typing import Iterable, Set

from app.models.canonical_paper import CanonicalPaper


def identifier_aliases(value: str | None) -> Set[str]:
    """Return conservative aliases for one provider or canonical identifier."""
    if not value:
        return set()

    raw = str(value).strip().lower()
    if not raw:
        return set()

    aliases = {raw}

    # DOI URLs and prefixes.
    if raw.startswith(("https://doi.org/", "http://doi.org/")):
        raw = raw.split("/", 3)[-1]
        aliases.add(raw)
    if raw.startswith("doi:"):
        raw = raw[4:]
        aliases.add(raw)
    if raw.startswith("10."):
        aliases.add(f"doi:{raw}")

    # OpenAlex URLs and prefixes.
    if raw.startswith("https://openalex.org/"):
        work_id = raw.rsplit("/", 1)[-1]
        aliases.update({work_id, f"openalex:{work_id}"})
    elif raw.startswith("openalex:"):
        aliases.add(raw.split(":", 1)[1])

    # S2 and PMID prefixes are commonly returned in both forms.
    for prefix in ("s2:", "pmid:", "pmc:"):
        if raw.startswith(prefix):
            aliases.add(raw.split(":", 1)[1])

    return aliases


def paper_identifier_aliases(paper: CanonicalPaper) -> Set[str]:
    """Return all aliases by which a canonical paper may appear upstream."""
    aliases: Set[str] = set()
    for value in (
        paper.canonical_id,
        paper.doi,
        paper.pmid,
        paper.semantic_scholar_id,
        paper.open_alex_id,
    ):
        aliases.update(identifier_aliases(value))
    return aliases


def relationship_target_map(
    papers: Iterable[CanonicalPaper],
) -> dict[str, str]:
    """Map every known provider alias to its canonical graph node ID."""
    targets: dict[str, str] = {}
    for paper in papers:
        for alias in paper_identifier_aliases(paper):
            targets.setdefault(alias, paper.canonical_id)
    return targets