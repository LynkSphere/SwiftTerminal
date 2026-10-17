/// Whether history supplies authoritative recency or needs local status-transition timestamps.
enum AgentActivityPolicy: Sendable {
    case providerTimestamp
    case observedTransitions
}
