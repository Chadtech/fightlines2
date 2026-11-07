//! Server-owned inactivity clocks. Presentation leases are bounded per turn,
//! so refreshes and unattended playback cannot keep a game alive indefinitely.
use juniper::{GraphQLEnum, GraphQLObject};
use std::time::{Duration, Instant};

const IDLE_PERIOD: Duration = Duration::from_secs(120);
const WARNING_PERIOD: Duration = Duration::from_secs(60);
const PLAYBACK_ALLOWANCE: Duration = Duration::from_secs(5 * 60);
const BRIEFING_ALLOWANCE: Duration = Duration::from_secs(120);

#[derive(Clone, Copy, GraphQLEnum)]
pub enum InactivityRenewalReason {
    UserInteraction,
    PlaybackAllowance,
    BriefingAllowance,
}

/// `None` at the game boundary means disabled; only an enabled game can carry
/// optional warning time. This is the same sum type as Elm's `Inactivity`.
#[derive(Debug, PartialEq, Eq, GraphQLObject)]
pub struct EnabledInactivity {
    pub warning_seconds_remaining: Option<i32>,
}

#[derive(Clone, Copy)]
pub struct ActivityClock {
    last_activity: Instant,
    turn_started: Instant,
}

impl ActivityClock {
    pub fn new(now: Instant) -> Self {
        Self {
            last_activity: now,
            turn_started: now,
        }
    }

    pub fn observe(&mut self, reason: InactivityRenewalReason, now: Instant) {
        let observed = match reason {
            InactivityRenewalReason::UserInteraction => now,
            InactivityRenewalReason::PlaybackAllowance => {
                now.min(self.turn_started + PLAYBACK_ALLOWANCE)
            }
            InactivityRenewalReason::BriefingAllowance => {
                now.min(self.turn_started + BRIEFING_ALLOWANCE)
            }
        };
        self.last_activity = self.last_activity.max(observed);
    }

    pub fn deadline(&self) -> Instant {
        self.last_activity + IDLE_PERIOD + WARNING_PERIOD
    }

    pub fn countdown_seconds(&self, now: Instant) -> Option<i32> {
        if now < self.last_activity + IDLE_PERIOD {
            return None;
        }
        let remaining = self.deadline().saturating_duration_since(now);
        Some(remaining.as_millis().div_ceil(1000) as i32)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn countdown_and_interaction_use_server_elapsed_time() {
        let now = Instant::now();
        let mut clock = ActivityClock::new(now);
        assert_eq!(
            clock.countdown_seconds(now + IDLE_PERIOD - Duration::from_millis(1)),
            None
        );
        assert_eq!(clock.countdown_seconds(now + IDLE_PERIOD), Some(60));
        assert_eq!(
            clock.countdown_seconds(clock.deadline() - Duration::from_millis(1)),
            Some(1)
        );
        assert_eq!(clock.countdown_seconds(clock.deadline()), Some(0));
        clock.observe(InactivityRenewalReason::UserInteraction, now + IDLE_PERIOD);
        assert_eq!(clock.countdown_seconds(now + IDLE_PERIOD), None);
        assert_eq!(clock.deadline(), now + IDLE_PERIOD * 2 + WARNING_PERIOD);
    }

    #[test]
    fn presentation_allowances_are_bounded_and_cannot_rewind_activity() {
        let now = Instant::now();
        for (reason, allowance) in [
            (
                InactivityRenewalReason::PlaybackAllowance,
                PLAYBACK_ALLOWANCE,
            ),
            (
                InactivityRenewalReason::BriefingAllowance,
                BRIEFING_ALLOWANCE,
            ),
        ] {
            let mut clock = ActivityClock::new(now);
            clock.observe(reason, now + Duration::from_secs(1));
            assert_eq!(clock.countdown_seconds(now + IDLE_PERIOD), None);
            clock.observe(reason, now + allowance * 10);
            assert_eq!(
                clock.deadline(),
                now + allowance + IDLE_PERIOD + WARNING_PERIOD
            );
            clock.observe(
                InactivityRenewalReason::UserInteraction,
                now + allowance * 11,
            );
            let deadline = clock.deadline();
            clock.observe(reason, now + allowance * 12);
            assert_eq!(clock.deadline(), deadline);
        }
    }
}
