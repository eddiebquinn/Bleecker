# Tasks for this change are minimal because this MR is spec-only.
# Step B (CRS L3 routing by hand), Step C (IaC of Step B), Step D
# (firewall rules by hand), and Step E (IaC of Step D) each ship
# as their own OpenSpec changes with their own tasks.md files.
# What lives here is the gating for merging THIS change and the
# follow-up bookkeeping after archive.

## 1. Pre-flight

- [ ] 1.1 Confirm the user is ready to ship the spec change
  (the four artifacts plus the change folder) onto
  `chore/openspec-phase1-proposal` and re-open / update MR
  !83.
- [ ] 1.2 Confirm `openspec validate
  phase1-1-crs-l3-routing-spec --strict` is green before
  raising the MR.

## 2. Ship the MR

- [ ] 2.1 Stage the four artifacts plus `openspec/config.yaml`
  onto `chore/openspec-phase1-proposal`. No other files. Do
  not stage `.hermes/`. Do not stage the prior change folder
  `openspec/changes/phase1-revert-argus-phase1/` (that was
  the wrong-framing attempt and was deleted from this branch
  at the reset).
- [ ] 2.2 Commit with a message that names the capability
  (`crs-l3-routing`), names the step (Step B's contract),
  and notes that Steps C / D / E are separate changes.
- [ ] 2.3 Push the branch and open / update MR !83 with the
  corrected title and description. Description must name the
  five steps and the spec-only nature of this change
  explicitly.

## 3. Reviewer checklist for the merge

- [ ] 3.1 Reviewer confirms the capability boundary: no
  firewall / ACL / mangle / PBR behaviour in `crs-l3-routing`.
- [ ] 3.2 Reviewer confirms the roles
  (`roles/routeros_l3_switch`, `roles/opnsense_firewall`)
  are not modified by this MR.
- [ ] 3.3 Reviewer confirms Step A's allow-all baseline is
  recorded as a precondition in the capability, not as part
  of the routing behaviour itself.
- [ ] 3.4 Reviewer confirms Step C is described as the
  future change that satisfies this capability against the
  by-hand Step B baseline.
- [ ] 3.5 Reviewer confirms Step D / Step E are explicitly
  out of scope here and will land as their own changes.

## 4. Post-merge

- [ ] 4.1 After merge, archive the change:
  `openspec archive phase1-1-crs-l3-routing-spec`. Confirm
  `openspec/specs/crs-l3-routing/spec.md` exists and matches
  the proposed spec content.
- [ ] 4.2 Update the user's phase notes with: spec merged,
  capability name `crs-l3-routing`, MR !83. Step B is the
  next objective.
- [ ] 4.3 Memorise the three durable facts from this session
  via the memory tool (separate from this turn — see the
  Wrap-up section the user will run after this MR is clean).

## 5. How Steps A-E read this spec

The spec is anchored to the Argus Phase 1.1 aim, not to any
single step. Each step reads it for the parts that step needs:

- [ ] 5.1 Operator entering Step B (CRS L3 by hand) confirms
  they have read the capability and understands the boundary:
  east/west at wire speed, north/south out the uplink to
  OPNsense, no firewall / ACL / mangle / PBR.
- [ ] 5.2 Operator confirms they have read the Step A baseline
  requirements (OPNsense allow-all; OPNsense is an L3
  bump-on-a-stick) and that those requirements are recorded
  in the phase notes as in-place. Step A is a precondition
  for the spec, not part of the spec itself.
- [ ] 5.3 Operator records the Step B by-hand configuration in
  the phase notes when it is applied. Step C opens its
  OpenSpec change by reading those notes; Step C's contract
  is the satisfaction of this spec against Step B's notes.
- [ ] 5.4 Step C (IaC of Step B) opens as its own OpenSpec
  change, reference material `roles/routeros_l3_switch`
  explicitly. Step C may refactor the role wholesale. Step
  C's acceptance test is `ansible-playbook site.yml --check`
  showing gridlink-1 in a state that satisfies this capability.
- [ ] 5.5 Step D (firewall rules by hand, phased rollout) opens
  as its own OpenSpec change with its own capability name
  (the spec is not amended; a new capability is added).
  Step D reads this spec only for "what is the routing
  layer Step D is laying firewall rules on top of".
- [ ] 5.6 Step E (IaC of Step D) opens as its own OpenSpec
  change. Step E may refactor `roles/opnsense_firewall`
  and `roles/routeros_l3_switch` wholesale.

Note: the device-side work for Steps A, B, and D is not an
OpenSpec change. Steps A and D changes are recorded in
phase notes; Step B changes are recorded in phase notes for
Step C to read.
