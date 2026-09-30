# Optional emergency fallback: AmneziaWG 3.1

AmneziaWG 3.1 is useful as an independent UDP-based fallback. It is intentionally not merged into the Xray automatic balancer.

Recommended use:
1. Install current AmneziaVPN/AmneziaWG-supported server components using official Amnezia instructions.
2. Generate a separate client configuration per device.
3. Keep it disabled normally.
4. If all Xray/TCP paths fail on a specific network, switch to the AmneziaWG profile.

As of September 2026, Amnezia documents 3.1 as the current generation and recommends moving away from 2.0.
