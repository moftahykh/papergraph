import math
from typing import List, Dict, Optional, Tuple
from app.models.canonical_paper import CanonicalPaper
from app.models.metric import MetricResult
from app.models.enums import MetricAvailability, ConfidenceLevel
from app.candidates.models import CandidateRecord
from app.enrichment.models import CandidateEnrichmentRecord
from app.ranking.models import (
    BaselineWeights,
    SignalContribution,
    ScoreBreakdown,
    RankedCandidate,
    RankingResult,
)
from app.ranking.prior import compute_prior_scores
from app.ranking.derivative import compute_derivative_scores


class SafeRankingEngine:
    """
    Deterministic, explainable hybrid ranking engine implementing PLAN.md Phase 6:
      - Baseline weights: Semantic (0.35), WBC (0.30), NCC (0.20), Direct link (0.15).
      - Strict Non-Negotiable Rule #6 & #8: Missing or errored signals are excluded from
        active signals and remaining weights are renormalized proportionally.
      - Never defaults missing signals to 0.0.
      - Evaluates PriorScore and DerivativeScore with mathematical bounds.
      - Strictly deterministic tie-breaking.
    """
    def __init__(self, weights: Optional[BaselineWeights] = None):
        self.weights = weights or BaselineWeights()

    def evaluate_candidate_signals(
        self,
        candidate_item: any,
    ) -> Dict[str, MetricResult]:
        """
        Extracts or formats the 4 component signals (semantic, wbc, ncc, direct)
        from either CandidateEnrichmentRecord or CandidateRecord.
        """
        # Determine underlying CandidateRecord
        if isinstance(candidate_item, CandidateEnrichmentRecord):
            enrich_rec = candidate_item
            cand_rec = enrich_rec.candidate
            wbc_metric = enrich_rec.wbc
            ncc_metric = enrich_rec.ncc
        elif isinstance(candidate_item, CandidateRecord):
            enrich_rec = None
            cand_rec = candidate_item
            wbc_metric = MetricResult(value=None, availability=MetricAvailability.UNAVAILABLE, reason="not_enriched")
            ncc_metric = MetricResult(value=None, availability=MetricAvailability.UNAVAILABLE, reason="not_enriched")
        else:
            raise ValueError(f"Unsupported candidate type: {type(candidate_item)}")

        signals: Dict[str, MetricResult] = {}

        # 1. Semantic signal
        if cand_rec.raw_semantic_score is not None:
            signals["semantic"] = MetricResult(
                value=min(1.0, max(0.0, cand_rec.raw_semantic_score)),
                availability=MetricAvailability.AVAILABLE,
            )
        elif "semantic" in cand_rec.pre_signals:
            signals["semantic"] = cand_rec.pre_signals["semantic"]
        else:
            signals["semantic"] = MetricResult(
                value=None,
                availability=MetricAvailability.UNAVAILABLE,
                reason="semantic_score_unavailable",
            )

        # 2. WBC signal
        signals["wbc"] = wbc_metric

        # 3. NCC signal
        signals["ncc"] = ncc_metric

        # 4. Direct relationship signal
        is_direct = cand_rec.is_direct_reference or cand_rec.is_direct_citation
        signals["direct"] = MetricResult(
            value=1.0 if is_direct else 0.0,
            availability=MetricAvailability.AVAILABLE,
        )

        return signals

    def compute_composite_score(
        self,
        signals: Dict[str, MetricResult],
    ) -> ScoreBreakdown:
        """
        Computes composite ranking score using proportional weight renormalization.
        """
        original_weights = self.weights.as_dict()
        
        # 1. Identify active (available) signals
        active_signals = {
            name: sig
            for name, sig in signals.items()
            if sig.availability == MetricAvailability.AVAILABLE and sig.value is not None
        }

        available_weight_sum = sum(original_weights[k] for k in active_signals.keys())
        contributions: Dict[str, SignalContribution] = {}

        # 2. Confidence level determination
        available_count = len(active_signals)
        if available_count >= 3:
            confidence = ConfidenceLevel.HIGH
        elif available_count == 2:
            confidence = ConfidenceLevel.MEDIUM
        elif available_count == 1:
            confidence = ConfidenceLevel.LOW
        else:
            confidence = ConfidenceLevel.INSUFFICIENT

        # 3. Handle zero available signals
        if available_count == 0 or available_weight_sum <= 0.0:
            for name, sig in signals.items():
                contributions[name] = SignalContribution(
                    name=name,
                    raw_value=sig.value,
                    availability=sig.availability,
                    original_weight=original_weights.get(name, 0.0),
                    normalized_weight=None,
                    weighted_score=None,
                    reason=sig.reason or "signal_unavailable",
                )
            return ScoreBreakdown(
                signals=contributions,
                available_weight_sum=0.0,
                final_score=None,
                confidence=ConfidenceLevel.INSUFFICIENT,
                available_signals_count=0,
            )

        # 4. Proportional weight renormalization
        final_score_acc = 0.0
        for name, sig in signals.items():
            orig_w = original_weights.get(name, 0.0)
            if name in active_signals:
                norm_w = orig_w / available_weight_sum
                weighted_val = norm_w * sig.value
                final_score_acc += weighted_val
                contributions[name] = SignalContribution(
                    name=name,
                    raw_value=sig.value,
                    availability=MetricAvailability.AVAILABLE,
                    original_weight=orig_w,
                    normalized_weight=round(norm_w, 6),
                    weighted_score=round(weighted_val, 6),
                    reason=None,
                )
            else:
                contributions[name] = SignalContribution(
                    name=name,
                    raw_value=None,
                    availability=sig.availability,
                    original_weight=orig_w,
                    normalized_weight=None,
                    weighted_score=None,
                    reason=sig.reason or "missing_signal",
                )

        clamped_score = min(1.0, max(0.0, round(final_score_acc, 6)))

        return ScoreBreakdown(
            signals=contributions,
            available_weight_sum=round(available_weight_sum, 6),
            final_score=clamped_score,
            confidence=confidence,
            available_signals_count=available_count,
        )

    def rank_candidates(
        self,
        origin: CanonicalPaper,
        candidates: List[any],
    ) -> RankingResult:
        """
        Executes full ranking pipeline: composite scoring, PriorScore,
        DerivativeScore, archetype assignment, and deterministic sorting.
        """
        if not candidates:
            return RankingResult(origin=origin, ranked_candidates=[])

        # 1. Compute composite scores and breakdowns
        initial_ranked: List[RankedCandidate] = []
        papers_list: List[CanonicalPaper] = []
        composite_scores_map: Dict[str, float] = {}

        for item in candidates:
            if isinstance(item, CandidateEnrichmentRecord):
                paper = item.candidate.paper
                enrich_rec = item
                cand_rec = item.candidate
            elif isinstance(item, CandidateRecord):
                paper = item.paper
                enrich_rec = None
                cand_rec = item
            else:
                continue

            signals = self.evaluate_candidate_signals(item)
            breakdown = self.compute_composite_score(signals)

            papers_list.append(paper)
            if breakdown.final_score is not None:
                composite_scores_map[paper.canonical_id] = breakdown.final_score

            initial_ranked.append(
                RankedCandidate(
                    paper=paper,
                    candidate_record=cand_rec,
                    enrichment_record=enrich_rec,
                    final_score=breakdown.final_score,
                    confidence=breakdown.confidence,
                    score_breakdown=breakdown,
                )
            )

        # 2. Compute PriorScore across candidate network
        prior_scores = compute_prior_scores(
            origin=origin,
            papers=papers_list,
            relevance_scores=composite_scores_map,
        )

        # 3. Compute DerivativeScore across candidate network
        derivative_scores = compute_derivative_scores(
            origin=origin,
            papers=papers_list,
        )

        # 4. Assign scores and classify archetypes
        origin_year = origin.year
        for rc in initial_ranked:
            pid = rc.paper.canonical_id
            rc.prior_score = prior_scores.get(pid, 0.0)
            rc.derivative_score = derivative_scores.get(pid, 0.0)

            # Archetype classification
            is_prior_candidate = (
                rc.prior_score >= 0.35 and (origin_year is None or rc.paper.year is None or rc.paper.year <= origin_year)
            )
            is_derivative_candidate = (
                rc.derivative_score >= 0.25 and (origin_year is None or rc.paper.year is None or rc.paper.year >= origin_year)
            )

            if is_prior_candidate and rc.prior_score > rc.derivative_score:
                rc.archetype = "prior_work"
            elif is_derivative_candidate:
                rc.archetype = "derivative_work"
            else:
                rc.archetype = "similar"

        # 5. Deterministic sorting
        # Primary: final_score descending (-1 if None)
        # Secondary: citation_count descending
        # Tertiary: canonical_id ascending
        def sort_key(rc: RankedCandidate):
            score_val = rc.final_score if rc.final_score is not None else -1.0
            cites = rc.paper.citation_count or 0
            return (-score_val, -cites, rc.paper.canonical_id)

        sorted_candidates = sorted(initial_ranked, key=sort_key)

        for i, rc in enumerate(sorted_candidates):
            rc.rank = i + 1

        prior_works = [rc for rc in sorted_candidates if rc.archetype == "prior_work"]
        derivative_works = [rc for rc in sorted_candidates if rc.archetype == "derivative_work"]

        # Confidence distribution
        conf_dist: Dict[str, int] = {}
        for rc in sorted_candidates:
            c_val = rc.confidence.value if hasattr(rc.confidence, "value") else str(rc.confidence)
            conf_dist[c_val] = conf_dist.get(c_val, 0) + 1

        return RankingResult(
            origin=origin,
            ranked_candidates=sorted_candidates,
            prior_works=prior_works,
            derivative_works=derivative_works,
            confidence_distribution=conf_dist,
        )
