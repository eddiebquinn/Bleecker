## Purpose

Describes the Layer 3 routing behaviour of gridlink-1 (CRS328)
between the homelab VLANs for the Argus Phase 1.1 aim. East/
west traffic is switched at wire speed via
hardware-offloaded SVIs; north/south traffic is forwarded to
OPNsense via the uplink. The capability is the contract Step C
(IaC of Step B) must satisfy, and it deliberately excludes
firewall, ACL, mangle, and PBR behaviour so that Step D's
firewall-rules contract does not have to re-litigate the
routing layer.

## ADDED Requirements

### Requirement: gridlink-1 routes inter-VLAN traffic at Layer 3

The gridlink-1 CRS328 SHALL route traffic between any two of
its configured VLAN subnets at Layer 3 using per-VLAN SVIs. The
SVIs SHALL be hardware-offloaded where the CRS328's switch-ASIC
supports it (RouterOS `l3-hw-offloading=yes`). East/west flows
between any pair of CRS-routed VLANs SHALL NOT be hairpinned to
OPNsense via the uplink.

#### Scenario: East/west flow between two CRS-routed VLANs

- **WHEN** a host on VLAN A (one of the CRS-routed VLANs) sends
  traffic to a host on VLAN B (another CRS-routed VLAN)
- **THEN** the CRS328 forwards the packets at Layer 3 between
  the two VLANs' SVIs
- **AND** the packets do not appear on the uplink to OPNsense

#### Scenario: Hardware offloading is enabled

- **WHEN** a CRS-routed VLAN's SVI is configured
- **THEN** the SVI is created with `l3-hw-offloading=yes`
- **AND** a flow between any two such VLANs runs at wire speed
  on the switch ASIC, not the CRS328's CPU

#### Scenario: A flow that exceeds the per-VLAN SVI hardware
  offloading limit falls back to software routing without
  dropping

- **WHEN** the CRS328 receives a flow that the switch-ASIC
  cannot offload (e.g. a flow that exceeds the hardware
  L3 table capacity or has a feature combination the ASIC
  does not support)
- **THEN** the flow is still routed at Layer 3 by the CRS328
  (CPU-routed)
- **AND** the flow does not silently fall back to hairpinning
  to OPNsense

### Requirement: gridlink-1 forwards north/south traffic to OPNsense via the uplink

Traffic destined for any subnet the gridlink-1 CRS328 does not
own SHALL be forwarded out the uplink to OPNsense (blackice-1)
as the next hop. North/south flows include any traffic destined
for OPNsense-routed VLANs, the internet, the management VLAN
when accessed from the upstream side, or any subnet that has
been explicitly delegated to OPNsense for routing.

#### Scenario: North/south flow to a subnet the CRS328 does not own

- **WHEN** a host on a CRS-routed VLAN sends traffic destined
  for a subnet that the CRS328 does not route (e.g. an
  OPNsense-routed VLAN, an internet-routed subnet, or an
  arbitrary external host)
- **THEN** the CRS328 forwards the packets out the uplink
  interface towards OPNsense

#### Scenario: Default route to OPNsense exists

- **WHEN** the CRS328's routing table is examined
- **THEN** a default route (or the equivalent catch-all for
  traffic destined outside the CRS-routed subnets) points at
  OPNsense's interface address on the management VLAN (or the
  relevant directly-connected OPNsense address)

#### Scenario: Return traffic for OPNsense-routed flows is
  handled symmetrically

- **WHEN** OPNsense routes return traffic for a flow back
  through the CRS328 (e.g. a response to a request that
  originated on an OPNsense-routed VLAN and was forwarded to
  the CRS328)
- **THEN** the CRS328 routes the return traffic to the
  originating VLAN's SVI at Layer 3

  Note: this requirement only covers routing, not the policy
  decision about whether the flow should have been on the CRS
  in the first place. That decision lives in Step D's
  capability.

### Requirement: The capability covers only Layer 3 routing; firewall, ACL, mangle, and PBR are out of scope

The `crs-l3-routing` capability SHALL NOT define or constrain
firewall rules, switch ACLs, mangle rules, or PBR (policy-based
routing / routing marks) on gridlink-1. Those concerns are
deliberately excluded and are addressed by separate
capabilities introduced when Step D of the wider Argus Phase
1.1 plan lands.

#### Scenario: No firewall filter rules are in scope

- **WHEN** the `crs-l3-routing` capability is read
- **THEN** the capability does not include any requirement
  about firewall filter rules, drop/accept semantics, or
  inter-VLAN policy
- **AND** any firewall filter behaviour on gridlink-1 belongs
  to a later capability

#### Scenario: No mangle or routing-mark rules are in scope

- **WHEN** the `crs-l3-routing` capability is read
- **THEN** the capability does not include any requirement
  about mangle rules, routing marks, or PBR
- **AND** any traffic-classification behaviour on gridlink-1
  belongs to a later capability

#### Scenario: OPNsense is treated as an L3 forwarding target,
  not a policy enforcement point, until Step D's capability lands

- **WHEN** Step B is in progress (the CRS L3 routing is
  being built by hand against the post-Step-A baseline
  where OPNsense has allow-all rules) and before Step D
  has been completed
- **THEN** the CRS328 routes east/west at wire speed and
  forwards north/south to OPNsense
- **AND** the CRS328 does not apply firewall, ACL, mangle,
  or PBR rules to enforce which flows are forwarded where
- **AND** OPNsense is observed to be an L3 bump-on-a-stick
  (allow-all rules in place) until Step D builds the
  firewall policy

### Requirement: Step C must satisfy the capability, not refactor the spec

A future OpenSpec change implementing Step C (IaC of the by-hand
Step B configuration) SHALL cause the resulting role
configuration to satisfy the requirements in this capability.
The change MAY refactor, replace, or rewrite
`roles/routeros_l3_switch` wholesale; it SHALL NOT amend this
spec without a separate OpenSpec change that updates the
capability explicitly.

#### Scenario: Step C ships a refactored role

- **WHEN** the Step C OpenSpec change lands
- **THEN** `roles/routeros_l3_switch` may be rewritten
  completely
- **AND** the resulting `ansible-playbook site.yml --check`
  dry-run output shows gridlink-1 in a state that satisfies
  this capability's routing requirements
- **AND** this capability remains unchanged

#### Scenario: Step C ships an additive change to the existing
  role

- **WHEN** the Step C OpenSpec change modifies
  `roles/routeros_l3_switch` in place rather than rewriting
  it
- **THEN** the additive changes still satisfy this capability's
  routing requirements
- **AND** any firewall / ACL / mangle / PBR work in the same
  role is left where it is, not removed and not enabled
  (Step D will handle that)

### Requirement: The Step A baseline is the precondition

The capability assumes the Step A baseline is in place on
blackice-1: OPNsense SHALL be reachable, OPNsense SHALL have
temporary allow-all rules between every pair of VLANs, and
OPNsense SHALL be acting as an L3 bump-on-a-stick. If the
Step A baseline is not in place, the capability's routing
requirements still hold, but the operational expectation
that east/west traffic flows without OPNsense policy
enforcement does not.

#### Scenario: Step A baseline verified before Step B begins

- **WHEN** the by-hand Step B work begins
- **THEN** the operator confirms OPNsense's rules are in the
  temporary allow-all state (recorded in the phase notes)
- **AND** the operator confirms OPNsense is advertising the
  necessary routes / VLAN interfaces so the CRS328's default
  route can resolve to it
- **AND** only then does the CRS328 routing begin

#### Scenario: Step A baseline is not in place

- **WHEN** the Step A baseline (OPNsense allow-all) is
  reverted by accident or by a misconfigured rule change
  during Step B
- **THEN** the CRS328 continues to satisfy this capability
  (east/west routing at wire speed; north/south forwarding
  out the uplink)
- **AND** the impact is on operational flows that now hit
  OPNsense's real rules, not on the routing layer itself
