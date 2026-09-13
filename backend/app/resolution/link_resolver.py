"""
Best-effort resolution for publisher landing-page URLs that carry no
machine-readable identifier inside the URL itself (e.g. IEEE Xplore,
ScienceDirect, MDPI article pages).

Strategy: fetch the page once and extract the standard `citation_*` /
`DC.identifier` HTML meta tags — the same metadata reference managers
(Zotero, Mendeley) rely on. Anything found is re-classified through
`classify_identifier` and resolved via the normal provider chain.

Safety notes:
- Only http(s) URLs, a single request, hard timeout, size-capped read.
- Any failure returns None; callers fall back to their normal error path.
"""
import logging
import re
from typing import Optional, Tuple

import httpx

from app.resolution.normalizers import classify_identifier

logger = logging.getLogger("papergraph.resolution.link_resolver")

_META_TAG_RE = re.compile(r"<meta\b[^>]*>", re.IGNORECASE)
_ATTR_RE = re.compile(r"([\w.\-]+)\s*=\s*[\"']([^\"']*)[\"']")

# Meta names known to carry a paper identifier we understand.
_KNOWN_META_KEYS = {
    "citation_doi",
    "citation_pmid",
    "citation_pmcid",
    "citation_arxiv_id",
    "dc.identifier",
}


async def resolve_url_to_identifier(
    url: str,
    timeout_seconds: float = 8.0,
    max_bytes: int = 600_000,
) -> Optional[Tuple[str, str]]:
    """
    Fetches a landing page once and returns the first usable (kind, value)
    identifier found in its meta tags, or None.
    """
    if not url.lower().startswith(("http://", "https://")):
        return None

    try:
        async with httpx.AsyncClient(
            timeout=timeout_seconds,
            follow_redirects=True,
            headers={
                "User-Agent": "PaperGraph/0.1 (+academic literature graph; research use)",
                "Accept": "text/html,*/*;q=0.8",
            },
        ) as client:
            response = await client.get(url)
            if response.status_code != 200:
                logger.info(f"Link resolver: HTTP {response.status_code} for {url}")
                return None
            html = response.text[:max_bytes]
    except Exception as e:
        logger.info(f"Link resolver: fetch failed for {url}: {e}")
        return None

    for tag in _META_TAG_RE.findall(html):
        attrs = {k.lower(): v for k, v in _ATTR_RE.findall(tag)}
        key = (attrs.get("name") or attrs.get("property") or "").strip().lower()
        if key not in _KNOWN_META_KEYS:
            continue
        content = (attrs.get("content") or "").strip()
        if not content:
            continue

        kind, value = classify_identifier(content)
        if kind not in ("url", "title"):
            logger.info(f"Link resolver: {url} -> {kind}:{value}")
            return (kind, value)

        # Trust the tag semantics even when the classifier is unsure
        # (e.g. DC.Identifier sometimes carries a bare DOI with odd casing).
        if key == "citation_doi" or key.startswith("dc.identif"):
            return ("doi", content)
        if key == "citation_pmid":
            return ("pmid", content)
        if key == "citation_pmcid":
            return ("pmcid", content)
        if key == "citation_arxiv_id":
            return ("arxiv", content)

    logger.info(f"Link resolver: no citation meta tags found for {url}")
    return None


NCBI_IDCONV_URL = "https://www.ncbi.nlm.nih.gov/pmc/utils/idconv/v1.0/"


async def resolve_ncbi_idconv(
    kind: str,
    value: str,
    timeout_seconds: float = 8.0,
) -> Optional[str]:
    """
    Deterministically maps a PMCID or PMID to a DOI (or PMID) via NCBI's
    official ID Converter API — the authoritative source for PubMed/PMC
    identifiers. This is the reliable path for brand-new biomedical papers
    that Semantic Scholar / OpenAlex have not indexed under the PMCID yet.

    Returns the best identifier string to feed back into the provider chain
    (a bare DOI, or "pmid:<id>" when no DOI exists), or None on any failure.
    """
    if kind not in ("pmcid", "pmid"):
        return None

    try:
        async with httpx.AsyncClient(timeout=timeout_seconds) as client:
            response = await client.get(
                NCBI_IDCONV_URL,
                params={
                    "ids": value,
                    "format": "json",
                    "tool": "papergraph",
                    "email": "papergraph@localhost.dev",
                },
            )
            if response.status_code != 200:
                logger.info(f"NCBI idconv: HTTP {response.status_code} for {value}")
                return None
            records = response.json().get("records") or []
            if not records:
                logger.info(f"NCBI idconv: no record for {value}")
                return None
            record = records[0]
            if record.get("doi"):
                return record["doi"]
            if record.get("pmid"):
                return f"pmid:{record['pmid']}"
    except Exception as e:
        logger.info(f"NCBI idconv failed for {value}: {e}")
    return None
