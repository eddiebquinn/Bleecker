## Context

The homelab network is split into VLANs by Project Blackwall.
gridlink-1 (CRS328) is the top-of-rack L2/L3 switch;
blackice-1 (R330 running OPNsense) is the firewall and L3
boundary. The 1Gb copper uplink between them has become the
bottleneck of the network: every inter-VLAN packet is
hairpinned up to OPNsense for policy enforcement, regardless of
whether it needs to be, and the 1Gb link saturates.

**Argus Phase 1.1 is the aim of moving east/west traffic off
OPNsense and onto the CRS328's L3 routing fabric.** The
CRS328 routes between VLANs locally at wire speed
(hardware-offloaded SVIs); north/south and any traffic destined
for subnets the CRS does not own is forwarded out the uplink to
OPNsense. Long-term the 1Gb uplink is being swapped for 10Gb
SFP+; that swap is out of scope for Argus Phase 1.1.

Phase 1.1 is structured as a sequence of objectives under the
aim:

- **Step A — temporary allow-all on OPNsense.** Done on the
  wire; recorded in the user's phase notes.
- **Step B — CRS L3 routing by hand.** The next objective.
  Build the routing on gridlink-1 via SSH, observe it working,
  get the 1Gb uplink off the saturated path.
- **Step C — IaC the CRS L3 routing.** This is what the
  `crs-l3-routing` capability exists to constrain.
- **Step D — Firewall rules by hand, phased rollout.** Switch
  ACLs and OPNsense rules land together, starting low-risk.
- **Step E — IaC the firewall rules.** Refactor the by-hand
  firewall into Ansible.

This MR documents the Argus Phase 1.1 spec for `crs-l3-routing`.
The capability is anchored to the aim, not to any specific step.
Step B produces the by-hand baseline; Step C ratifies Step B
against this spec; Step D and Step E land as separate capabilities
on separate OpenSpec changes. The repository holds reference
material from the failed Phase 1.1 attempt (visible
in the `0d05b98` / `b9fcb29` lineage as the catch-and-punt
mangle, the routing marks, and the `red_flag_patterns`
mechanics). That reference material is not authoritative; the
spec is. Step C and Step E will likely refactor those roles
wholesale.

The failed Phase 1.1 attempt also placed firewall rules on
OPNsense first, then attempted to layer CRS L3 routing on top
of those rules. The sunk-cost recognition that triggered the
Steps plan was that approach: backing out the firewall rules
meant admitting the first attempt was wasted. Step A (the
allow-all that replaces the legacy firewall rules) is the
clean-break baseline the new attempt is starting from.

## Goals / Non-Goals

**Goals:**

- Document the L3 routing behaviour gridlink-1 must satisfy for
  the Argus Phase 1.1 aim: east/west between CRS-routed VLANs at
  wire speed; north/south out the uplink to OPNsense; nothing else.
  Step B produces the by-hand baseline against this spec; Step C
  ratifies that baseline.
- Make the Step C contract explicit so that when the by-hand
  Step B config lands in Ansible, the implementation has a
  written acceptance test instead of an assumed one.
- Make the Step D boundary explicit so the Step D capability
  does not have to re-litigate routing semantics or duplicate
  this spec.
- Acknowledge that the existing
  `roles/routeros_l3_switch` and `roles/opnsense_firewall`
  roles in the repository are reference material, not
  authoritative for the new spec, and may be refactored when
  Step C / Step E land.

**Non-Goals:**

- This change does not refactor or modify the existing
  Ansible roles, playbooks, group_vars, or CI jobs. Those are
  reference material and stay as-is until Step C / Step E.
- This change does not perform Step B. Step B is hand-run on
  the device and is not in this MR's scope. The spec describes
  what Step B must achieve, not the act of doing it.
- This change does not introduce the OPNsense firewall-rules
  capability for Step D / Step E. Those are separate OpenSpec
  changes with their own capability names.
- This change does not commit to a specific OPNsense transport
  (REST API vs SSH). The transport was a question raised
  during the failed Phase 1.1 attempt; Step E will settle it.
  `crs-l3-routing` is the CRS328's contract only.

## Decisions

### Decision 1: This is a spec change only — no repo edits

The first instinct on a "Phase 1 of the wider plan" change is
to clean up the roles / playbooks / group_vars / CI jobs in
the repo. That instinct is wrong here: the existing code is
the reference material Step C / Step E refactor against, and
premature cleanup removes that reference value.

**Chosen:** this MR adds four files (proposal, design, tasks,
`specs/crs-l3-routing/spec.md`) and the OpenSpec config. It
modifies no other file. The capability itself declares the
existing code non-authoritative so that Step C and Step E do
not have to fight "the role already says X" assumptions.

**Alternatives considered:**

- Surgical revert of the `l3-*.yml` files and the L3-related
  group_vars (the `vlan_topology` / `red_flag_patterns` /
  `opnsense_static_routes` blocks), keeping Phase 1.1's role
  implementations. Rejected: the failed Phase 1.1 attempt's
  shape is itself being thrown away under the "redo from the
  ground up" decision; partial reverts keep the misleading
  half around.
- Full strip back to pre-`2642e36`. Rejected: nukes the
  reference material Step C and Step E need.

### Decision 2: The capability boundary covers L3 routing only; firewall/ACL/mangle/PBR are out

The capability `crs-l3-routing` describes what gridlink-1 does
at Layer 3 between VLANs for the Argus Phase 1.1 aim, and is
the contract that Step C ratifies Step B's by-hand baseline
against. The capability explicitly excludes firewall, ACL,
mangle, and PBR. Step D's capability will introduce those
concerns.

**Chosen:** two positive requirements (route east/west;
forward north/south) plus two boundary requirements (out of
scope; reference-material disclaimer). The boundary
requirements are there because Step D will be done by someone
who can read the spec; without the boundary requirements, the
spec would be ambiguous about whether firewall behaviour is
"not yet implemented" or "explicitly forbidden".

**Alternatives considered:**

- Include the firewall / ACL / mangle / PBR behaviour in the
  same capability. Rejected: doubles the spec size and forces
  Step D to amend the spec before it can land.
- Leave Step D's behaviour unspecified. Rejected: leaves the
  capability incomplete and Step D starts from zero context.

### Decision 3: Steps / Phase naming

The user prefers "Steps A-E" for the Phase 1.1 sequence, with
Phase 1.1 as the aim and Steps as the objectives under it.
Phase 1.1 is the *aim*; Steps are the *objectives*. This
distinction matters because OpenSpec treats each change as a
discrete proposal; lumping Step B and Step C into a "Phase 3"
change would mishape the contract.

**Chosen:** the change folder name is
`phase1-1-crs-l3-routing-spec` — names the aim
(`phase1-1`), names the step (`crs-l3-routing`), names the
artefact kind (`spec`). The capabilities and changes for
Steps D and E will be separate OpenSpec changes with their
own folder names.

**Alternatives considered:**

- `phase3-stepb-crs-l3-routing-iac`. Rejected: ties the
  change to a phase that hasn't been designated as such.
- `crs-l3-routing`. Tempting, but ambiguous with the eventual
  Step C change, which is also "the CRS L3 routing change".

### Decision 4: Roles stay non-authoritative

The existing `roles/routeros_l3_switch` and
`roles/opnsense_firewall` are reference material for Step C
and Step E. They are not authoritative for the new spec.
The capability records this so that Step C does not feel
required to preserve the existing role shape.

**Chosen:** the capability includes "Step C may refactor the
role wholesale" as a scenario. The proposal says so directly
in the Impact section.

**Alternatives considered:**

- Delete the roles now. Rejected: removes reference material
  Step C / Step E want to read; the user has explicitly said
  the roles "should not be treated as authoritative" but
  also should not be removed (see Q3 in the prior turn).
- Re-author the roles in this MR. Rejected: out of scope;
  this MR is spec-only.

## Risks / Trade-offs

- **Risk: someone reads the capability and concludes the
  existing role should already satisfy it.** → Mitigation:
  the capability's "Step C may refactor the role wholesale"
  scenario, and the proposal's Impact section, both make the
  "reference material, not authoritative" point explicit.
  Steps C and E both read this MR before opening their own.

- **Risk: Step C's OpenSpec change is opened as "update the
  existing role" rather than "rewrite the role against the
  contract".** → Mitigation: the capability's Step C scenario
  allows both shapes; the proposal's impact section names the
  rewrite shape first as the natural option.

- **Risk: Step D opens before Step C lands and amends this
  capability to fold in the firewall behaviour.** → Mitigation:
  Step D's capability should be a separate name
  (e.g. `switch-acl-punt-to-opnsense`,
  `opnsense-firewall-rules`). If Step D amends `crs-l3-routing`
  instead of creating a new capability, the MR is paused and
  Step D is asked to split into "amendment + new capability".

- **Risk: the Step A baseline is treated as part of Step B's
  contract.** → Mitigation: the capability's "Step A baseline
  is the precondition" requirement makes the baseline a
  precondition, not part of the routing behaviour. Step A's
  changes happen outside this capability.

- **Risk: the OPNsense transport question (REST API vs SSH)
  bleeds into this MR.** → Mitigation: this MR is the CRS328's
  contract. OPNsense is mentioned only as the upstream next
  hop; the transport is Step E's decision.

- **Trade-off: a thin capability carries less signal.** → This
  is intentional. Step C's capability (when it lands) will
  carry the implementation-specific signal; Step D's capability
  will carry the firewall signal. This one carries the
  routing-layer signal only.

## Migration Plan

There is no migration surface in this MR. It is a spec change.
Step B, Step C, Step D, and Step E each carry their own
migration plans when they ship.

### Rollback

- **Spec rollback:** revert the merge commit. The
  `crs-l3-routing` capability disappears from
  `openspec/specs/` after the change is archived (and the
  archived spec is revertable as a separate revert).
- **Step B rollback:** not relevant to this MR. Step B is a
  hand-run change on the device; its rollback path is whatever
  the operator used to set the routing up in the first place.

## Open Questions

None at the spec level. Two questions stay with the wider
plan and are answered by future changes, not by this MR:

- The OPNsense transport (REST API vs SSH) is a Step E
  question. It does not affect `crs-l3-routing`.
- The eventual `l3-routing` enablement (which `red_flag_patterns`
  classify as "risky enough to punt", in what order, with what
  ACL shape on the switch side) is a Step D question. It does
  not affect `crs-l3-routing`.
