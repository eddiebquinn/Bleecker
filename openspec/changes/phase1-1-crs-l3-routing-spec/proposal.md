## Why

Project Blackwall split the homelab into VLANs with gridlink-1 (CRS328)
as the top-of-rack L2/L3 switch and blackice-1 (R330 running OPNsense)
as the firewall / L3 boundary. The 1Gb copper link between them became
saturated because every inter-VLAN packet — including bulk east/west
traffic with no policy reason to be inspected — was hairpinned up to
OPNsense for filtering.

**Argus Phase 1.1 is the aim of taking east/west off OPNsense and
putting it on the CRS328's L3 routing fabric.** The CRS328 will route
between VLANs locally at wire speed (hardware-offloaded SVIs) and
forward only north/south traffic to OPNsense. Long-term the 1Gb uplink
will be swapped for 10Gb SFP+; that swap is out of scope for Argus
Phase 1.1.

Phase 1.1 is being delivered as a sequence of objectives (Steps A
through E) under the aim:

- **Step A — temporary allow-all on OPNsense.** Done. OPNsense is
  currently an L3 bump-on-a-stick with allow-all rules; no policy
  enforcement active. This makes the CRS L3 routing observable
  without policy in the way.
- **Step B — CRS L3 routing by hand.** Build the routing on
  gridlink-1 directly via SSH. No firewall rules, no mangle, no
  PBR, no punting. Just routing. Verify east/west flows correctly
  and the 1Gb uplink no longer hairpins bulk traffic.
- **Step C — IaC the CRS L3 routing.** Take the by-hand config
  produced in Step B and replicate it through
  `roles/routeros_l3_switch`.
- **Step D — Firewall rules by hand, phased rollout.** Apply
  firewall rules to both devices by hand, starting with the
  low-risk VLANs (IoT, Guest, etc.) and working toward the
  high-risk ones (DMZ, Management, anything to the IDP). The
  switch's basic ACL layer and the OPNsense rule layer land
  together; traffic classification — "this flow stays on the CRS,
  this flow punts to OPNsense for full inspection" — comes alive
  in this step. Example punted flows from the rollout plan: IDP
  traffic, port 53 (DNS), port 22 (SSH), DMZ VLAN traffic,
  Management VLAN traffic.
- **Step E — IaC the firewall rules.** Refactor and harden the
  by-hand firewall configuration into Ansible roles for both
  devices.

This MR documents the Argus Phase 1.1 spec for `crs-l3-routing`:
the contract that gridlink-1 must satisfy as an L3 router between
VLANs, regardless of which step produces the working state. The
spec is anchored to the aim, not to a single step. Step B
produces the by-hand baseline; Step C ratifies it against this
spec; Step D and Step E each carry their own contracts and are
separate OpenSpec changes.

The sunk-cost recognition that triggered the Steps A-E plan: a
previous attempt at Argus Phase 1.1 began with placing firewall
rules on OPNsense, then tried to bolt the CRS L3 routing on top
of those rules rather than backing them out. That attempt failed
(visible in the `0d05b98` / `b9fcb29` lineage as the catch-and-punt
mangle and the mixed-direction routing marks) and the L3 routing
is being re-attempted from a clean Step A baseline.

## What Changes

- **New capability `crs-l3-routing`.** Spec describes gridlink-1 as
  a Layer 3 switch between the homelab VLANs: east/west traffic is
  routed at wire speed using hardware-offloaded SVIs; north/south
  traffic is forwarded out the uplink to OPNsense; no firewall, ACL,
  mangle, or PBR behaviour is in scope for this capability. New spec
  file: `specs/crs-l3-routing/spec.md`.
- **No repo edits.** This MR is spec-only. The repository continues
  to hold the Phase 1.1 attempt's code (`roles/routeros_l3_switch`,
  `roles/opnsense_firewall`, `playbooks/network/`, the network
  group_vars, the network CI jobs). That code is reference material
  for Step C / Step E, not authoritative for the new spec, and may
  be refactored wholesale when those steps land. The capability
  carries this point explicitly so that Step C and Step E do not
  start from "this role implements the contract" assumptions.
- **No device edits.** Step A is done. Step B starts after this MR
  merges. Step B is hand-run against gridlink-1 over SSH; it is
  not in this MR's scope.
- **No CI changes.** No new CI jobs. No job deletions (the
  `ansible-network-*` jobs stay as-is and continue to be
  reference material for the eventual rewrite).

## Capabilities

### New Capabilities

- `crs-l3-routing`: gridlink-1 (CRS328) routes traffic between
  the homelab VLANs at Layer 3. East/west traffic between CRS-routed
  VLANs flows wire-speed via hardware-offloaded SVIs; north/south
  traffic (and any traffic destined for subnets the switch does
  not own) is forwarded out the uplink to OPNsense. No firewall
  rules, no ACLs, no mangle, no PBR. The capability is anchored
  to the Argus Phase 1.1 aim, not to any specific step. Step B
  produces the by-hand baseline; Step C ratifies Step B against
  the capability; Step D and Step E land as separate capabilities
  on separate OpenSpec changes.

### Modified Capabilities

None. `openspec/specs/` is empty prior to this change; there is no
existing capability to delta against.

## Impact

- Repository: only `openspec/` is touched (the new change folder).
  The existing roles, playbooks, group_vars, and CI jobs are
  unaffected. They are explicitly designated as non-authoritative
  reference material for the wider aim.
- Wire state: unchanged by this MR. Step A is captured in the
  user's phase notes (allow-all on OPNsense; OPNsense acting as
  L3 bump-on-a-stick). Step B starts against that baseline.
- Downstream changes:
  - **Step C** (IaC of Step B): a future OpenSpec change. The
    `crs-l3-routing` capability is its acceptance contract; the
    `roles/routeros_l3_switch` role may be refactored wholesale
    when that change lands.
  - **Step D** (firewall by hand): a future OpenSpec change with
    its own capability (likely covering switch ACLs and OPNsense
    rules, with the punt-to-OPNsense classification rules). It is
    NOT in scope for `crs-l3-routing`.
  - **Step E** (IaC of Step D): a future OpenSpec change. The
    `roles/opnsense_firewall` role and any switch-ACL role land
    or are refactored at that point.
- OPNsense transport: the Phase 1.1 attempt's `discover-state.yml`
  reads OPNsense via the REST API; the `opnsense_firewall` role
  uses REST GETs for read-only verification. The transport is not
  in scope for `crs-l3-routing` (which is switch behaviour) but is
  noted as a reference-material decision for Step C / Step E:
  Step E will revisit whether the OPNsense transport stays REST or
  moves to SSH, based on whatever limitations produced the
  Step A's allow-all rules.
- Risk surface: low. This MR adds spec text. The capability is
  testable against the by-hand baseline Step B produces (Step C
  is the ratification; Step C is when the role is checked against
  the contract).
