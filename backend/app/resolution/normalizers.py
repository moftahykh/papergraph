import re
from typing import Optional


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
