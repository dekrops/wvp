import Verified.Evidence
import Verified.Chain
import Verified.Registry
import Verified.Contract.Theorems
import Verified.Contract.Typing
import Verified.Contract.Limits

-- check.sh checks the dependency report, including transitive axioms. This file covers the
-- protocol's definitions; the model of one ledger is audited beside it, where that is kept.
#print axioms Verified.verification_sound
#print axioms Verified.order_fulfillment
#print axioms Verified.wrong_order_rejected
#print axioms Verified.disallowed_transition_rejected
#print axioms Verified.verifyAll_iff
#print axioms Verified.verified_requires_satisfaction
#print axioms Verified.unauthenticated_cannot_verify
#print axioms Verified.inadmissible_additions_cannot_verify
#print axioms Verified.authentic_agent_statement_does_not_verify
#print axioms Verified.authoritative_statement_verifies
#print axioms Verified.linked_sequence
#print axioms Verified.valid_chain_is_contiguous
#print axioms Verified.linked_prefix
#print axioms Verified.truncation_is_undetectable
-- Claim registry states (Verified/Registry.lean).
#print axioms Verified.closeOne_id_state_final
#print axioms Verified.claimant_cannot_close_disputed
#print axioms Verified.final_claims_persist
#print axioms Verified.disputes_keep_states
#print axioms Verified.eq_of_same_id
#print axioms Verified.map_keeps_ids
#print axioms Verified.map_preserves_exclusive
#print axioms Verified.closeStep_preserves_exclusive
#print axioms Verified.register_preserves_exclusive
#print axioms Verified.openDispute_preserves_exclusive
#print axioms Verified.step_preserves_exclusive
#print axioms Verified.run_preserves_exclusive
#print axioms Verified.accepted_log_units_exclusive
#print axioms Verified.register_respects_limit
#print axioms Verified.replacement_comes_next
-- Work Contract Language 1 (Verified/Contract).
#print axioms Verified.Contract.truth_tables
#print axioms Verified.Contract.de_morgan
#print axioms Verified.Contract.not_not
#print axioms Verified.Contract.and_eq_true
#print axioms Verified.Contract.and_eq_false
#print axioms Verified.Contract.or_eq_true
#print axioms Verified.Contract.or_eq_false
#print axioms Verified.Contract.not_eq_true
#print axioms Verified.Contract.not_eq_false
#print axioms Verified.Contract.any_eq_true
#print axioms Verified.Contract.any_eq_false
#print axioms Verified.Contract.all_eq_true
#print axioms Verified.Contract.all_eq_false
#print axioms Verified.Contract.bound_get
#print axioms Verified.Contract.term_shape
#print axioms Verified.Contract.comparable_is_definite
#print axioms Verified.Contract.wellTyped_safe
#print axioms Verified.Contract.wellTyped_comparison_unknown_only_if_absent
#print axioms Verified.Contract.unaccepted_fact_changes_nothing
#print axioms Verified.Contract.supported_iff_all_true
#print axioms Verified.Contract.contradicted_iff_some_false
#print axioms Verified.Contract.unknown_requirement_prevents_support
#print axioms Verified.Contract.exists_true_has_witness
#print axioms Verified.Contract.exists_false_requires_closed
#print axioms Verified.Contract.forall_true_requires_closed
#print axioms Verified.Contract.forall_false_has_counterexample
#print axioms Verified.Contract.no_records_open_kind_is_unknown
#print axioms Verified.Contract.term_eval_extends
#print axioms Verified.Contract.eval_monotone
#print axioms Verified.Contract.definite_decision_is_stable
#print axioms Verified.Contract.evaluation_is_deterministic
#print axioms Verified.Contract.late_record_in_complete_listing_overturns_support
#print axioms Verified.Contract.late_record_in_complete_listing_overturns_contradiction
#print axioms Verified.Contract.withdrawn_completeness_loses_the_decision
#print axioms Verified.Contract.undetermined_can_become_either
