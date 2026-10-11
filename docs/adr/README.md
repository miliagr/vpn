# Architecture Decision Records

Every serious fix or change gets an ADR in this directory, written in the same commit as the change.

"Serious" means any of:
- a fix for a user-visible failure (the VPN does not connect, is unstable, or leaks traffic);
- a change to network behaviour: firewall, NAT, MTU/MSS, DNS, routing, ports, transports;
- a change to a security invariant or to how secrets are handled;
- a change to the deployment flow or to what a host runs;
- anything that needs a server reinstall or new client profiles.

Typos, doc rewording, test-only changes and refactors without behaviour change do not need one.

## Format

File name: `NNNN-short-title.md`, numbered from `0001` in order. Never renumber; to reverse a decision, add a new ADR and set the old one's status to `Superseded by NNNN`.

```markdown
# NNNN. Title

Date: YYYY-MM-DD
Status: Accepted

## Context
What was observed (symptoms, evidence, how it was reproduced) and the root cause.

## Decision
What was changed and why this way.

## Alternatives considered
What else was possible and why it was rejected.

## Consequences
What changes for the servers and the clients, manual steps (redeploy, re-import profiles), how to verify, how to roll back.
```

Never put UUIDs, keys, short IDs, VLESS links or WireGuard private keys in an ADR.
