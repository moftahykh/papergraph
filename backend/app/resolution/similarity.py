from app.resolution.normalizers import normalize_title


def levenshtein_distance(s1: str, s2: str) -> int:
    """
    Computes Levenshtein edit distance between two strings using dynamic programming.
    Memory-efficient O(min(m, n)) space complexity.
    """
    if s1 == s2:
        return 0
    if not s1:
        return len(s2)
    if not s2:
        return len(s1)

    if len(s1) < len(s2):
        s1, s2 = s2, s1

    previous_row = list(range(len(s2) + 1))
    for i, c1 in enumerate(s1):
        current_row = [i + 1] + [0] * len(s2)
        for j, c2 in enumerate(s2):
            insertions = previous_row[j + 1] + 1
            deletions = current_row[j] + 1
            substitutions = previous_row[j] + (c1 != c2)
            current_row[j + 1] = min(insertions, deletions, substitutions)
        previous_row = current_row

    return previous_row[-1]


STOP_WORDS = {
    "a", "an", "the", "and", "or", "of", "in", "on", "at", "to", "for", "with", "by", "from", "as", "about", "into", "through"
}


def token_sort_ratio(s1: str, s2: str, filter_stopwords: bool = True) -> float:
    """
    Computes Token Sort Ratio between two strings in range [0.0, 1.0].
    Tokenizes, removes punctuation, sorts words alphabetically, and compares via edit distance.
    Optionally evaluates both raw and stopword-filtered forms to maximize matching fidelity.
    """
    norm1 = normalize_title(s1)
    norm2 = normalize_title(s2)

    if not norm1 or not norm2:
        return 1.0 if norm1 == norm2 else 0.0
    if norm1 == norm2:
        return 1.0

    # 1. Raw sorted comparison
    words1 = norm1.split()
    words2 = norm2.split()
    sorted1 = " ".join(sorted(words1))
    sorted2 = " ".join(sorted(words2))

    if sorted1 == sorted2:
        return 1.0

    dist = levenshtein_distance(sorted1, sorted2)
    max_len = max(len(sorted1), len(sorted2))
    raw_ratio = 1.0 - (dist / max_len) if max_len > 0 else 1.0

    if not filter_stopwords:
        return max(0.0, min(1.0, raw_ratio))

    # 2. Stopword-filtered comparison
    filt1 = [w for w in words1 if w not in STOP_WORDS]
    filt2 = [w for w in words2 if w not in STOP_WORDS]
    if filt1 and filt2:
        s_filt1 = " ".join(sorted(filt1))
        s_filt2 = " ".join(sorted(filt2))
        if s_filt1 == s_filt2:
            return 1.0
        f_dist = levenshtein_distance(s_filt1, s_filt2)
        f_max = max(len(s_filt1), len(s_filt2))
        f_ratio = 1.0 - (f_dist / f_max) if f_max > 0 else 1.0
        return max(0.0, min(1.0, max(raw_ratio, f_ratio)))

    return max(0.0, min(1.0, raw_ratio))


def is_title_match(
    title1: str, title2: str, threshold: float = 0.92
) -> tuple[bool, float]:
    """
    Determines if two titles represent the same publication based on Token Sort Ratio.
    Returns (is_match, score).
    """
    ratio = token_sort_ratio(title1, title2, filter_stopwords=True)
    return (ratio >= threshold, round(ratio, 4))
