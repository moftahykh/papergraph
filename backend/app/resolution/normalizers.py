import re
from typing import Optional, Tuple


def normalize_doi(doi: Optional[str]) -> Optional[str]:
    """
    Normalizes any DOI form (URL wrapper, doi: prefix, uppercase) to a lowercase bare DOI.
    Returns None if the string does not contain a valid DOI pattern.
    """
    if not doi:
        return None
    cleaned = doi.strip().lower()
    
    # Strip URL wrappers and prefixes
    prefixes = [
        "https://doi.org/",
        "http://doi.org/",
        "https://dx.doi.org/",
        "http://dx.doi.org/",
        "doi:",
        "dx.doi.org/",
    ]
    for prefix in prefixes:
        if cleaned.startswith(prefix):
            cleaned = cleaned[len(prefix):].strip()

    # Basic DOI structure validation: must start with '10.' and have a slash
    if re.match(r"^10\.\d{4,9}/[-._;()/:a-z0-9]+$", cleaned):
        return cleaned
    
    # Tolerant fallback if it contains 10.xxxx/
    match = re.search(r"10\.\d{4,9}/[-._;()/:a-z0-9]+", cleaned)
    if match:
        return match.group(0).strip().rstrip(".")
    
    return None if not cleaned else cleaned


def normalize_pmid(pmid: Optional[str]) -> Optional[str]:
    """
    Normalizes PubMed IDs by stripping prefixes and non-digit characters.
    """
    if not pmid:
        return None
    cleaned = pmid.strip().lower()
    for prefix in ["pmid:", "pubmed:", "pmid"]:
        if cleaned.startswith(prefix):
            cleaned = cleaned[len(prefix):].strip()
    
    digits = re.sub(r"\D", "", cleaned)
    return digits if digits else None


def normalize_title(title: Optional[str]) -> str:
    """
    Produces a normalized title string for deduplication:
    lowercased, punctuation removed, and whitespace collapsed.
    """
    if not title:
        return ""
    # Remove HTML tags if present
    text = re.sub(r"<[^>]+>", "", title)
    # Remove punctuation and special characters
    text = re.sub(r"[^\w\s]", " ", text.lower())
    # Collapse multiple whitespace characters
    return " ".join(text.split())


def extract_first_author_surname(authors: list) -> str:
    """
    Extracts the family name / surname of the first author in lowercase.
    Handles 'First Last', 'Last, First', and single name inputs.
    """
    if not authors:
        return ""
    
    first = authors[0]
    name = first.name if hasattr(first, "name") else str(first)
    if not name or name.lower() in ["unknown author", "unknown"]:
        return ""
    
    # Clean whitespace
    name = name.strip().lower()
    
    # Check for "Family, Given" format
    if "," in name:
        return name.split(",")[0].strip()
    
    # Check for "Given Family" format
    parts = name.split()
    if len(parts) == 1:
        return parts[0]
    
    # If last part is suffix (Jr., III, etc.), pick previous
    if parts[-1].rstrip(".") in ["jr", "sr", "ii", "iii", "iv", "phd", "md"]:
        return parts[-2] if len(parts) > 2 else parts[0]
        
    return parts[-1]


def build_deterministic_key(title: str, first_author: str, year: Optional[int]) -> str:
    """
    Builds a normalized title + first author surname + year deterministic lookup key.
    """
    norm_t = normalize_title(title)
    norm_a = first_author.strip().lower()
    year_str = str(year) if year else "none"
    return f"{norm_t}|{norm_a}|{year_str}"


def classify_identifier(raw: Optional[str]) -> Tuple[str, str]:
    """
    Universal paper-identifier classifier.

    Accepts anything a researcher might paste — bare DOI, DOI URL, PMID,
    PMCID, arXiv ID, S2 paper ID, CorpusID, OpenAlex ID, or a publisher
    landing-page URL (PubMed, PMC, arXiv, OpenAlex, Semantic Scholar,
    Nature, ACM, Wiley, Science, Springer, bioRxiv, Taylor & Francis, OUP...).

    Returns (kind, value) where kind is one of:
      "doi" | "pmid" | "pmcid" | "arxiv" | "s2" | "corpusid" | "openalex"
      | "url"   — http(s) link we cannot identify locally (caller may scrape
                  citation_* meta tags as a best-effort fallback)
      | "title" — free text to search by
    """
    if not raw:
        return ("title", "")

    text = raw.strip()
    low = text.lower()

    # ---- URL inputs ----
    if low.startswith(("http://", "https://")):
        host_match = re.search(r"^https?://([^/?#]+)", low)
        host = host_match.group(1) if host_match else ""

        if "pmc.ncbi.nlm.nih.gov" in host:
            m = re.search(r"(pmc\d+)", low)
            if m:
                return ("pmcid", m.group(1).upper())

        if "pubmed.ncbi.nlm.nih.gov" in host:
            m = re.search(r"/(\d{5,10})(?:/|$)", low)
            if m:
                return ("pmid", m.group(1))

        if "arxiv.org" in host:
            m = re.search(
                r"/(?:abs|pdf|html)/([0-9]{4}\.[0-9]{4,5}|[a-z\-]+(?:\.[a-z]{2})?/[0-9]{7})",
                low,
            )
            if m:
                return ("arxiv", m.group(1))

        if "openalex.org" in host:
            m = re.search(r"(w\d{1,12})", low)
            if m:
                return ("openalex", m.group(1).upper())

        if "semanticscholar.org" in host:
            m = re.search(r"([0-9a-f]{40})", low)
            if m:
                return ("s2", m.group(1))

        # Publisher URLs that embed the DOI in the path
        # (ACM, Wiley, Science, Springer, Taylor & Francis, bioRxiv, OUP...)
        if "10." in low:
            doi = normalize_doi(text)
            if doi:
                doi = re.sub(
                    r"(\.(?:pdf|html?)|/(?:full|abstract|epdf|pdf|short|meta|references|suppl[a-z0-9._\-]*))+$",
                    "",
                    doi,
                    flags=re.IGNORECASE,
                )
                return ("doi", doi)

        # Nature article slugs are DOI suffixes (10.1038/<slug>)
        if "nature.com" in host:
            m = re.search(r"/articles/([a-z0-9][a-z0-9\-]+)", low)
            if m:
                return ("doi", f"10.1038/{m.group(1)}")

        # Unknown landing page — the caller may scrape citation_* meta tags.
        return ("url", text)

    # ---- Bare / prefixed identifiers ----
    if low.startswith("10.") or "doi.org/" in low or low.startswith("doi:"):
        doi = normalize_doi(text)
        if doi:
            return ("doi", doi)

    m = re.match(r"^(?:pmcid:)?(pmc\d{3,12})$", low)
    if m:
        return ("pmcid", m.group(1).upper())

    m = re.match(r"^(?:pmid:|pubmed:)?(\d{5,10})$", low)
    if m:
        return ("pmid", m.group(1))

    m = re.match(r"^(?:arxiv:)?([0-9]{4}\.[0-9]{4,5})(v\d+)?$", low)
    if m:
        return ("arxiv", m.group(1))

    m = re.match(r"^(?:arxiv:)?([a-z\-]+(?:\.[a-z]{2})?/[0-9]{7})(v\d+)?$", low)
    if m:
        return ("arxiv", m.group(1))

    m = re.match(r"^(?:https?://)?(?:api\.)?openalex\.org/(?:works/)?(w\d{1,12})$", low)
    if m:
        return ("openalex", m.group(1).upper())

    m = re.match(r"^(w\d{1,12})$", low)
    if m:
        return ("openalex", m.group(1).upper())

    m = re.match(r"^(?:s2:)?([0-9a-f]{40})$", low)
    if m:
        return ("s2", m.group(1))

    m = re.match(r"^corpusid:?(\d{1,12})$", low)
    if m:
        return ("corpusid", m.group(1))

    return ("title", text)
