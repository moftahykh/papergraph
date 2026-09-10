from typing import List, Optional, Dict, Tuple, Union
from app.models.canonical_paper import CanonicalPaper
from app.providers.models import RawPaper
from app.resolution.normalizers import (
    normalize_doi,
    normalize_pmid,
    normalize_title,
    extract_first_author_surname,
    build_deterministic_key,
)
from app.resolution.similarity import token_sort_ratio, is_title_match
from app.resolution.merger import merge_canonical_papers


class IdentityResolver:
    """
    Orchestrates multi-source academic paper deduplication and identity resolution.
    Strictly adheres to the 6-tier resolution priority:
    1. Exact DOI match
    2. Exact PMID match
    3. Exact provider identifier match (S2 ID, OpenAlex ID)
    4. Normalized Title + First Author Surname + Year match
    5. Fuzzy Title match (Token Sort Ratio >= 0.92)
    6. Manual Disambiguation fallback (returns candidates when confidence < 0.85)
    """
    def __init__(self):
        self.canonical_papers: List[CanonicalPaper] = []
        self._doi_map: Dict[str, CanonicalPaper] = {}
        self._pmid_map: Dict[str, CanonicalPaper] = {}
        self._provider_id_map: Dict[str, CanonicalPaper] = {}
        self._deterministic_map: Dict[str, CanonicalPaper] = {}

    def _index_paper(self, paper: CanonicalPaper) -> None:
        """Indexes paper across all lookup tables."""
        if paper.doi:
            clean = normalize_doi(paper.doi)
            if clean:
                self._doi_map[clean] = paper

        if paper.pmid:
            clean = normalize_pmid(paper.pmid)
            if clean:
                self._pmid_map[clean] = paper

        if paper.semantic_scholar_id:
            self._provider_id_map[f"s2:{paper.semantic_scholar_id}"] = paper

        if paper.open_alex_id:
            clean_oa = paper.open_alex_id.split("/")[-1]
            self._provider_id_map[f"openalex:{clean_oa}"] = paper

        # Deterministic key
        first_author = extract_first_author_surname(paper.authors)
        if paper.title and first_author:
            key = build_deterministic_key(paper.title, first_author, paper.year)
            self._deterministic_map[key] = paper

    def _remove_from_indices(self, paper: CanonicalPaper) -> None:
        """Removes older unmerged paper instance before re-indexing merged record."""
        if paper.doi:
            clean = normalize_doi(paper.doi)
            if clean in self._doi_map and self._doi_map[clean] == paper:
                del self._doi_map[clean]

        if paper.pmid:
            clean = normalize_pmid(paper.pmid)
            if clean in self._pmid_map and self._pmid_map[clean] == paper:
                del self._pmid_map[clean]

        first_author = extract_first_author_surname(paper.authors)
        if paper.title and first_author:
            key = build_deterministic_key(paper.title, first_author, paper.year)
            if key in self._deterministic_map and self._deterministic_map[key] == paper:
                del self._deterministic_map[key]

        if paper in self.canonical_papers:
            self.canonical_papers.remove(paper)

    def find_match(self, candidate: CanonicalPaper) -> Tuple[Optional[CanonicalPaper], str, float]:
        """
        Searches for an existing matching record adhering to the 6-tier priority.
        Returns (matched_paper, match_strategy, confidence).
        """
        # Tier 1: Exact DOI Match
        if candidate.doi:
            clean_doi = normalize_doi(candidate.doi)
            if clean_doi and clean_doi in self._doi_map:
                return self._doi_map[clean_doi], "exact_doi", 1.0

        # Tier 2: Exact PMID Match
        if candidate.pmid:
            clean_pmid = normalize_pmid(candidate.pmid)
            if clean_pmid and clean_pmid in self._pmid_map:
                return self._pmid_map[clean_pmid], "exact_pmid", 1.0

        # Tier 3: Exact Provider Identifier Match
        if candidate.semantic_scholar_id:
            key = f"s2:{candidate.semantic_scholar_id}"
            if key in self._provider_id_map:
                return self._provider_id_map[key], "provider_id", 0.99

        if candidate.open_alex_id:
            clean_oa = candidate.open_alex_id.split("/")[-1]
            key = f"openalex:{clean_oa}"
            if key in self._provider_id_map:
                return self._provider_id_map[key], "provider_id", 0.99

        # Tier 4: Normalized Title + First Author Surname + Year Match
        first_author = extract_first_author_surname(candidate.authors)
        if candidate.title and first_author:
            key = build_deterministic_key(candidate.title, first_author, candidate.year)
            if key in self._deterministic_map:
                return self._deterministic_map[key], "deterministic_hash", 0.95

        # Tier 5: Fuzzy Title Matching (Token Sort Ratio >= 0.92)
        norm_title = candidate.normalized_title or normalize_title(candidate.title)
        best_match: Optional[CanonicalPaper] = None
        highest_ratio: float = 0.0

        for existing in self.canonical_papers:
            # Rule: Distinct explicit DOIs or PMIDs must never be fuzzy-merged
            if candidate.doi and existing.doi:
                if normalize_doi(candidate.doi) != normalize_doi(existing.doi):
                    continue
            if candidate.pmid and existing.pmid:
                if normalize_pmid(candidate.pmid) != normalize_pmid(existing.pmid):
                    continue

            matched, ratio = is_title_match(norm_title, existing.normalized_title, threshold=0.92)
            if matched and ratio > highest_ratio:
                # Check year compatibility: same year or unknown year
                if (
                    candidate.year is None
                    or existing.year is None
                    or abs(candidate.year - existing.year) <= 1
                ):
                    highest_ratio = ratio
                    best_match = existing

        if best_match and highest_ratio >= 0.92:
            return best_match, "fuzzy_title", round(highest_ratio, 4)

        return None, "none", 0.0

    def ingest(self, item: Union[RawPaper, CanonicalPaper]) -> CanonicalPaper:
        """
        Ingests a raw paper or canonical paper into the resolver.
        If a match is found, merges the records in-place and re-indexes.
        If no match is found, creates a new canonical entry.
        """
        candidate = item.to_canonical() if isinstance(item, RawPaper) else item

        existing, strategy, confidence = self.find_match(candidate)
        if existing:
            # Merge candidate into existing
            merged = merge_canonical_papers(existing, candidate)
            self._remove_from_indices(existing)
            self.canonical_papers.append(merged)
            self._index_paper(merged)
            return merged
        else:
            # New unique canonical paper
            self.canonical_papers.append(candidate)
            self._index_paper(candidate)
            return candidate

    def ingest_batch(
        self, items: List[Union[RawPaper, CanonicalPaper]]
    ) -> List[CanonicalPaper]:
        """Ingests and deduplicates a collection of papers."""
        for item in items:
            self.ingest(item)
        return list(self.canonical_papers)

    def disambiguate_title_query(
        self,
        query: str,
        candidates: List[CanonicalPaper],
    ) -> Tuple[bool, Optional[CanonicalPaper], List[CanonicalPaper], float]:
        """
        Tier 6: Disambiguation evaluation.
        If query title matches a single paper with high confidence (>= 0.85), returns (True, paper, [], 1.0).
        If ambiguous or multiple close candidates exist, returns (False, None, candidates, confidence)
        prompting the client for manual researcher disambiguation.
        """
        norm_query = normalize_title(query)
        scored_candidates: List[Tuple[CanonicalPaper, float]] = []

        for p in candidates:
            norm_title = p.normalized_title or normalize_title(p.title)
            ratio = token_sort_ratio(norm_query, norm_title)
            if ratio >= 0.60:
                scored_candidates.append((p, ratio))

        scored_candidates.sort(key=lambda x: x[1], reverse=True)

        if not scored_candidates:
            return False, None, [], 0.0

        top_paper, top_score = scored_candidates[0]

        # Exact match
        if top_score >= 0.95 and (
            len(scored_candidates) == 1 or scored_candidates[1][1] < 0.80
        ):
            return True, top_paper, [], top_score

        # Ambiguous case: multiple papers with close high scores
        if len(scored_candidates) > 1 and (top_score - scored_candidates[1][1]) < 0.10:
            return (
                False,
                None,
                [item[0] for item in scored_candidates[:5]],
                round(top_score, 2),
            )

        # Single candidate with moderate/high confidence
        if top_score >= 0.85:
            return True, top_paper, [], top_score

        # Low confidence (< 0.85): return for manual disambiguation
        return (
            False,
            None,
            [item[0] for item in scored_candidates[:5]],
            round(top_score, 2),
        )
