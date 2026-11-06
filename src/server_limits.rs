//! Server-wide CPU admission and bounded, per-client mutation budgets.
use crate::{server_log, session_token::SessionToken};
use actix_web::HttpRequest;
use juniper::{FieldError, graphql_value};
use std::{
    collections::BTreeMap,
    net::IpAddr,
    sync::{
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

const MAX_RATE_BUCKETS: usize = 8192;
const CLEANUP_INTERVAL: Duration = Duration::from_secs(60);

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Operation {
    CreateLobby,
    JoinMatchMaking,
    SubmitTurn,
    SendChat,
    SubmitFeedback,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum ClientAddress {
    Ip(IpAddr),
    Unavailable,
}

impl ClientAddress {
    pub fn from_request(request: &HttpRequest) -> Self {
        let Some(peer) = request.peer_addr() else {
            return Self::Unavailable;
        };
        let peer = peer.ip().to_canonical();
        // Only the same-machine proxy may supply an address. The rightmost hop
        // is Caddy's direct client, even when an earlier proxy supplied a chain.
        if peer.is_loopback()
            && let Some(address) = request
                .headers()
                .get_all("x-forwarded-for")
                .last()
                .and_then(|value| value.to_str().ok())
                .and_then(|value| value.rsplit(',').next())
                .and_then(|value| value.trim().parse::<IpAddr>().ok())
        {
            return Self::Ip(address.to_canonical());
        }
        Self::Ip(peer)
    }
}

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Client {
    Address(ClientAddress),
    Session(SessionToken),
}

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
struct RateKey {
    client: Client,
    operation: Operation,
}

struct Budget {
    burst: u32,
    refill_every: Duration,
}

impl RateKey {
    fn budget(&self) -> Budget {
        match (&self.client, self.operation) {
            (Client::Session(_), Operation::CreateLobby | Operation::JoinMatchMaking) => Budget {
                burst: 3,
                refill_every: Duration::from_secs(60),
            },
            (Client::Address(_), Operation::CreateLobby | Operation::JoinMatchMaking) => Budget {
                burst: 10,
                refill_every: Duration::from_secs(15),
            },
            (Client::Session(_), Operation::SendChat) => Budget {
                burst: 8,
                refill_every: Duration::from_secs(2),
            },
            (Client::Address(_), Operation::SendChat) => Budget {
                burst: 24,
                refill_every: Duration::from_millis(500),
            },
            (Client::Session(_), Operation::SubmitFeedback) => Budget {
                burst: 2,
                refill_every: Duration::from_secs(300),
            },
            (Client::Address(_), Operation::SubmitFeedback) => Budget {
                burst: 5,
                refill_every: Duration::from_secs(60),
            },
            (Client::Session(_), Operation::SubmitTurn) => Budget {
                burst: 6,
                refill_every: Duration::from_secs(2),
            },
            (Client::Address(_), Operation::SubmitTurn) => Budget {
                burst: 24,
                refill_every: Duration::from_millis(500),
            },
        }
    }
}

struct Rates {
    // The instant when all previously consumed tokens will have refilled.
    refilled_at: BTreeMap<RateKey, Instant>,
    next_cleanup: Instant,
}

impl Default for Rates {
    fn default() -> Self {
        Self {
            refilled_at: BTreeMap::new(),
            next_cleanup: Instant::now() + CLEANUP_INTERVAL,
        }
    }
}

#[derive(Default)]
pub struct Limits {
    ai_active: AtomicBool,
    rates: Mutex<Rates>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Rejection {
    AiBusy,
    RateLimited { retry_after: Duration },
    Capacity,
    Unavailable,
}

impl std::fmt::Display for Rejection {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(formatter, "{self:?}")
    }
}

impl std::error::Error for Rejection {}

impl Rejection {
    pub fn into_field_error(self) -> FieldError {
        let (message, code, retry_seconds) = match self {
            Rejection::AiBusy => (
                "the ai is busy with another game. please try again shortly.".to_owned(),
                "AI_BUSY",
                1,
            ),
            Rejection::RateLimited { retry_after } => {
                let seconds = retry_after.as_secs().max(1)
                    + u64::from(retry_after.as_secs() > 0 && retry_after.subsec_nanos() > 0);
                (
                    format!("too many requests. please try again in {seconds} seconds."),
                    "RATE_LIMITED",
                    seconds as i32,
                )
            }
            Rejection::Capacity => (
                "the server is busy. please try again in 60 seconds.".to_owned(),
                "SERVER_BUSY",
                60,
            ),
            Rejection::Unavailable => {
                tracing::error!(
                    event = "mutation_limits_unavailable",
                    "mutation limits lock is poisoned"
                );
                return server_log::internal_error(
                    "the server is unavailable. please try again shortly.",
                );
            }
        };
        FieldError::new(
            message,
            graphql_value!({
                "code": code, "retryAfterSeconds": retry_seconds,
            }),
        )
    }
}

/// Held by the blocking worker, including when the HTTP client disconnects.
pub struct AiPermit<'a>(&'a AtomicBool);

impl Drop for AiPermit<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}

impl Limits {
    pub fn acquire_ai(&self) -> Result<AiPermit<'_>, Rejection> {
        self.ai_active
            .compare_exchange(false, true, Ordering::Acquire, Ordering::Relaxed)
            .map(|_| AiPermit(&self.ai_active))
            .map_err(|_| Rejection::AiBusy)
    }

    pub fn admit(
        &self,
        operation: Operation,
        address: ClientAddress,
        session: Option<SessionToken>,
    ) -> Result<(), Rejection> {
        self.admit_at(operation, address, session, Instant::now())
    }

    fn admit_at(
        &self,
        operation: Operation,
        address: ClientAddress,
        session: Option<SessionToken>,
        now: Instant,
    ) -> Result<(), Rejection> {
        let mut rates = self.rates.lock().map_err(|_| Rejection::Unavailable)?;
        if now >= rates.next_cleanup {
            rates
                .refilled_at
                .retain(|_, refilled_at| *refilled_at > now);
            rates.next_cleanup = now + CLEANUP_INTERVAL;
        }
        let mut keys = vec![RateKey {
            client: Client::Address(address),
            operation,
        }];
        if let Some(session) = session {
            keys.push(RateKey {
                client: Client::Session(session),
                operation,
            });
        }
        let mut retry_after = Duration::ZERO;
        let mut missing = 0;
        for key in &keys {
            if let Some(refilled_at) = rates.refilled_at.get(key) {
                let budget = key.budget();
                let debt = refilled_at.saturating_duration_since(now);
                retry_after =
                    retry_after.max(debt.saturating_sub(budget.refill_every * (budget.burst - 1)));
            } else {
                missing += 1;
            }
        }
        if !retry_after.is_zero() {
            return Err(Rejection::RateLimited { retry_after });
        }
        // Never evict a live budget: rotating cookies/addresses cannot reset it.
        if rates.refilled_at.len() + missing > MAX_RATE_BUCKETS {
            return Err(Rejection::Capacity);
        }
        // Check both budgets before consuming either. Rejected calls do not
        // delay refill; each resolver invocation (including aliases) is counted.
        for key in keys {
            let refill_every = key.budget().refill_every;
            let refilled_at = rates.refilled_at.entry(key).or_insert(now);
            *refilled_at = (*refilled_at).max(now) + refill_every;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{FixtureValue, TestResult};
    use actix_web::test::TestRequest;

    #[test]
    fn client_address_only_trusts_the_last_proxy_hop_from_loopback() -> TestResult<()> {
        for (peer, forwarded, expected) in [
            ("192.0.2.1:1234", "198.51.100.1", "192.0.2.1"),
            ("127.0.0.1:1234", "198.51.100.1, 192.0.2.1", "192.0.2.1"),
            ("[::ffff:127.0.0.1]:1234", "::ffff:192.0.2.1", "192.0.2.1"),
            ("[::1]:1234", "2001:db8::1", "2001:db8::1"),
            ("127.0.0.1:1234", "192.0.2.1, invalid", "127.0.0.1"),
        ] {
            let request = TestRequest::post()
                .peer_addr(peer.parse()?)
                .insert_header(("x-forwarded-for", forwarded))
                .to_http_request();
            assert_eq!(
                ClientAddress::from_request(&request),
                ClientAddress::Ip(expected.parse()?)
            );
        }
        let request = TestRequest::post()
            .insert_header(("x-forwarded-for", "192.0.2.1"))
            .to_http_request();
        assert_eq!(
            ClientAddress::from_request(&request),
            ClientAddress::Unavailable
        );
        Ok(())
    }

    #[test]
    fn session_budget_refills_and_rejections_do_not_consume_address_budget() -> TestResult<()> {
        let limits = Limits::default();
        let now = Instant::now();
        let session = SessionToken::from_token("host".into());
        let address = ClientAddress::Ip("192.0.2.1".parse()?);
        for _ in 0..3 {
            limits.admit_at(Operation::CreateLobby, address, Some(session.clone()), now)?;
        }
        for _ in 0..20 {
            assert_eq!(
                limits.admit_at(Operation::CreateLobby, address, Some(session.clone()), now),
                Err(Rejection::RateLimited {
                    retry_after: Duration::from_secs(60)
                })
            );
        }
        // A different session behind the same NAT still has its initial burst.
        limits.admit_at(
            Operation::CreateLobby,
            address,
            Some(SessionToken::from_token("guest".into())),
            now,
        )?;
        assert!(
            limits
                .admit_at(
                    Operation::CreateLobby,
                    address,
                    Some(session.clone()),
                    now + Duration::from_secs(59)
                )
                .is_err()
        );
        limits.admit_at(
            Operation::CreateLobby,
            address,
            Some(session),
            now + Duration::from_secs(60),
        )?;
        Ok(())
    }

    #[test]
    fn address_budget_survives_rotating_cookies_and_session_budget_survives_ip_changes()
    -> TestResult<()> {
        let limits = Limits::default();
        let now = Instant::now();
        let address = ClientAddress::Ip("192.0.2.1".parse()?);
        for index in 0..10 {
            limits.admit_at(
                Operation::CreateLobby,
                address,
                Some(SessionToken::from_token(index.to_string())),
                now,
            )?;
        }
        assert_eq!(
            limits.admit_at(Operation::CreateLobby, address, None, now),
            Err(Rejection::RateLimited {
                retry_after: Duration::from_secs(15)
            })
        );
        limits.admit_at(
            Operation::CreateLobby,
            address,
            None,
            now + Duration::from_secs(15),
        )?;
        let session = SessionToken::from_token("mobile player".into());
        for index in 1..=6 {
            limits.admit_at(
                Operation::SubmitTurn,
                ClientAddress::Ip(format!("198.51.100.{index}").parse()?),
                Some(session.clone()),
                now,
            )?;
        }
        let other = ClientAddress::Ip("203.0.113.1".parse()?);
        assert_eq!(
            limits.admit_at(Operation::SubmitTurn, other, Some(session.clone()), now),
            Err(Rejection::RateLimited {
                retry_after: Duration::from_secs(2)
            })
        );
        limits.admit_at(
            Operation::SubmitTurn,
            other,
            Some(session),
            now + Duration::from_secs(2),
        )?;
        Ok(())
    }

    #[test]
    fn operations_have_independent_budgets_and_address_turns_refill() -> TestResult<()> {
        let limits = Limits::default();
        let now = Instant::now();
        let address = ClientAddress::Unavailable;
        for _ in 0..10 {
            limits.admit_at(Operation::CreateLobby, address, None, now)?;
        }
        for _ in 0..24 {
            limits.admit_at(Operation::SubmitTurn, address, None, now)?;
        }
        assert_eq!(
            limits.admit_at(Operation::SubmitTurn, address, None, now),
            Err(Rejection::RateLimited {
                retry_after: Duration::from_millis(500)
            })
        );
        limits.admit_at(
            Operation::SubmitTurn,
            address,
            None,
            now + Duration::from_millis(500),
        )?;
        Ok(())
    }

    #[test]
    fn chat_and_feedback_limits_survive_rotating_sessions_and_refill_independently()
    -> TestResult<()> {
        let limits = Limits::default();
        let now = Instant::now();
        let address = ClientAddress::Ip("192.0.2.1".parse()?);
        let session = SessionToken::from_token("chat player".into());
        for _ in 0..8 {
            limits.admit_at(Operation::SendChat, address, Some(session.clone()), now)?;
        }
        assert_eq!(
            limits.admit_at(
                Operation::SendChat,
                ClientAddress::Unavailable,
                Some(session.clone()),
                now
            ),
            Err(Rejection::RateLimited {
                retry_after: Duration::from_secs(2)
            })
        );
        limits.admit_at(
            Operation::SendChat,
            address,
            Some(session.clone()),
            now + Duration::from_secs(2),
        )?;
        for index in 0..5 {
            limits.admit_at(
                Operation::SubmitFeedback,
                address,
                Some(SessionToken::from_token(index.to_string())),
                now,
            )?;
        }
        assert_eq!(
            limits.admit_at(Operation::SubmitFeedback, address, None, now),
            Err(Rejection::RateLimited {
                retry_after: Duration::from_secs(60)
            })
        );
        limits.admit_at(
            Operation::SubmitFeedback,
            address,
            None,
            now + Duration::from_secs(60),
        )?;
        // A shared session remains limited even when the address changes.
        for _ in 0..2 {
            limits.admit_at(
                Operation::SubmitFeedback,
                ClientAddress::Unavailable,
                Some(session.clone()),
                now,
            )?;
        }
        assert_eq!(
            limits.admit_at(
                Operation::SubmitFeedback,
                address,
                Some(session.clone()),
                now
            ),
            Err(Rejection::RateLimited {
                retry_after: Duration::from_secs(300)
            })
        );
        limits.admit_at(
            Operation::SubmitFeedback,
            address,
            Some(session),
            now + Duration::from_secs(300),
        )?;
        Ok(())
    }

    #[test]
    fn rate_storage_is_bounded_and_cleanup_preserves_active_budgets() -> TestResult<()> {
        let limits = Limits::default();
        let now = Instant::now();
        // The shared address bucket plus session buckets fill the bounded table.
        {
            let mut rates = limits.rates.lock().fixture()?;
            for index in 0..MAX_RATE_BUCKETS {
                rates.refilled_at.insert(
                    RateKey {
                        client: Client::Session(SessionToken::from_token(index.to_string())),
                        operation: Operation::CreateLobby,
                    },
                    now + Duration::from_secs(120),
                );
            }
            rates.next_cleanup = now;
        }
        assert_eq!(
            limits.admit_at(
                Operation::CreateLobby,
                ClientAddress::Unavailable,
                None,
                now
            ),
            Err(Rejection::Capacity)
        );
        assert_eq!(
            limits.rates.lock().fixture()?.refilled_at.len(),
            MAX_RATE_BUCKETS
        );
        limits.admit_at(
            Operation::CreateLobby,
            ClientAddress::Unavailable,
            None,
            now + Duration::from_secs(120),
        )?;
        assert_eq!(limits.rates.lock().fixture()?.refilled_at.len(), 1);
        Ok(())
    }

    #[test]
    fn ai_admission_is_shared_across_workers_and_released_on_drop() -> TestResult<()> {
        let limits = std::sync::Arc::new(Limits::default());
        let permit = limits.acquire_ai().fixture()?;
        let other = limits.clone();
        let rejected = std::thread::spawn(move || other.acquire_ai().err())
            .join()
            .map_err(|_| "AI admission worker panicked")?;
        assert_eq!(rejected, Some(Rejection::AiBusy));
        drop(permit);
        assert!(limits.acquire_ai().is_ok());
        Ok(())
    }
}
