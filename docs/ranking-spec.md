# PaperGraph Ranking Specification

> Status: Specification Draft (Phase 0 Initialized / Implemented in Phase 6)

## 1. Weighted Bibliographic Coupling (WBC)

Measures similarity based on shared outbound references, normalized with epsilon protection:
$$\text{WBC}(u, v) = \frac{\sum_{k \in R_u \cap R_v} w_k}{\sqrt{\sum_{k \in R_u} w_k \cdot \sum_{k \in R_v} w_k} + \epsilon}$$

## 2. Normalized Co-Citation (NCC)

Measures similarity based on papers citing both works:
$$\text{NCC}(u, v) = \frac{|C_u \cap C_v|}{\sqrt{|C_u| \cdot |C_v|} + \epsilon}$$

## 3. Signal Renormalization

Missing metrics are treated as nullable rather than zero. For available signals $A$:
$$\text{NormalizedWeight}_i = \frac{W_i}{\sum_{j \in A} W_j}$$
$$\text{FinalScore} = \sum_{i \in A} \text{NormalizedWeight}_i \cdot \text{Score}_i$$
