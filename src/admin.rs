//! Operator authentication is separate from player identities and deterministic game seeds.
// Keep Rust support files separate from Elm's case-sensitive Admin namespace.
#[path = "admin_server/dashboard.rs"]
pub mod dashboard;
#[cfg(test)]
#[path = "admin_server/tests.rs"]
mod tests;

use crate::{environment::Environment, server_log};
use actix_web::{
    HttpRequest,
    cookie::{Cookie, SameSite},
};
use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier, password_hash::SaltString};
use base64::{Engine, engine::general_purpose::URL_SAFE_NO_PAD};
use juniper::{FieldResult, GraphQLEnum};
use std::{
    collections::{BTreeMap, VecDeque},
    env, io,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

const COOKIE: &str = "fightlines_admin";
const SESSION_LIFETIME: Duration = Duration::from_secs(8 * 60 * 60);
const MAX_SESSIONS: usize = 32;

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Token(String);

#[derive(Clone, Copy, Debug, PartialEq, Eq, GraphQLEnum)]
pub enum SessionStatus {
    Disabled,
    SignedOut,
    SignedIn,
}

pub enum CookieChange {
    Set(Token),
    Remove,
}

pub struct Access {
    auth: Arc<Auth>,
    token: Mutex<Option<Token>>,
    cookie_change: Mutex<Option<CookieChange>>,
    same_origin: bool,
}

impl Access {
    pub fn from_request(auth: Arc<Auth>, request: &HttpRequest, environment: Environment) -> Self {
        Self {
            auth,
            token: Mutex::new(Token::from_request(request)),
            cookie_change: Mutex::new(None),
            same_origin: same_origin(request, environment),
        }
    }
    pub fn disabled() -> Self {
        Self {
            auth: Arc::new(Auth::default()),
            token: Mutex::new(None),
            cookie_change: Mutex::new(None),
            same_origin: false,
        }
    }
    pub fn take_cookie_change(&self) -> Option<CookieChange> {
        self.cookie_change
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
            .take()
    }

    pub fn status(&self) -> FieldResult<SessionStatus> {
        self.auth.status(
            self.token.lock().map_err(|_| unavailable())?.as_ref(),
            Instant::now(),
        )
    }
    fn require_origin(&self) -> FieldResult<()> {
        if self.same_origin {
            Ok(())
        } else {
            Err("admin requests must come from this site's origin.".into())
        }
    }
    pub fn require(&self) -> FieldResult<()> {
        self.require_origin()?;
        self.auth
            .require(self.token.lock().map_err(|_| unavailable())?.as_ref())
    }
    pub fn login(&self, password: &str) -> FieldResult<SessionStatus> {
        self.require_origin()?;
        let mut token = self.token.lock().map_err(|_| unavailable())?;
        let next = self.auth.login(password, token.as_ref(), Instant::now())?;
        *self.cookie_change.lock().map_err(|_| unavailable())? =
            Some(CookieChange::Set(next.clone()));
        *token = Some(next);
        Ok(SessionStatus::SignedIn)
    }
    pub fn logout(&self) -> FieldResult<bool> {
        self.require_origin()?;
        let mut token = self.token.lock().map_err(|_| unavailable())?;
        self.auth.logout(token.as_ref())?;
        *token = None;
        *self.cookie_change.lock().map_err(|_| unavailable())? = Some(CookieChange::Remove);
        Ok(true)
    }
}

#[derive(Default)]
pub struct Auth {
    password_hash: Option<String>,
    sessions: Mutex<BTreeMap<Token, Instant>>,
    attempts: Mutex<VecDeque<Instant>>,
    verifying: AtomicBool,
}

impl Auth {
    pub fn load() -> io::Result<Self> {
        let value = env::var("FIGHTLINES_ADMIN_PASSWORD_HASH").map_err(|error| match error {
            env::VarError::NotPresent => {
                io::Error::new(io::ErrorKind::NotFound, "admin is disabled")
            }
            _ => io::Error::new(io::ErrorKind::InvalidInput, "invalid admin password hash"),
        });
        match value {
            Ok(value) => Self::from_hash(Some(value)),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Self::from_hash(None),
            Err(error) => Err(error),
        }
    }

    pub fn from_hash(password_hash: Option<String>) -> io::Result<Self> {
        if let Some(value) = &password_hash {
            let hash = PasswordHash::new(value).map_err(|_| invalid_hash())?;
            let params = argon2::Params::try_from(&hash).map_err(|_| invalid_hash())?;
            if hash.algorithm.as_str() != "argon2id"
                || hash.version != Some(19)
                || hash.salt.is_none()
                || hash.hash.is_none()
                || params.m_cost() < 19456
                || params.m_cost() > 65536
                || params.t_cost() < 2
                || params.t_cost() > 5
                || params.p_cost() != 1
            {
                return Err(invalid_hash());
            }
        }
        Ok(Self {
            password_hash,
            sessions: Mutex::new(BTreeMap::new()),
            attempts: Mutex::new(VecDeque::new()),
            verifying: AtomicBool::new(false),
        })
    }

    pub fn status(&self, token: Option<&Token>, now: Instant) -> FieldResult<SessionStatus> {
        if self.password_hash.is_none() {
            return Ok(SessionStatus::Disabled);
        }
        let mut sessions = self.sessions.lock().map_err(|_| unavailable())?;
        sessions.retain(|_, expires| *expires > now);
        Ok(if token.is_some_and(|token| sessions.contains_key(token)) {
            SessionStatus::SignedIn
        } else {
            SessionStatus::SignedOut
        })
    }

    pub fn require(&self, token: Option<&Token>) -> FieldResult<()> {
        if self.status(token, Instant::now())? == SessionStatus::SignedIn {
            Ok(())
        } else {
            Err(juniper::FieldError::new(
                "admin login required.",
                juniper::graphql_value!({"code": "ADMIN_LOGIN_REQUIRED"}),
            ))
        }
    }

    pub fn login(
        &self,
        password: &str,
        previous: Option<&Token>,
        now: Instant,
    ) -> FieldResult<Token> {
        let encoded = self
            .password_hash
            .as_ref()
            .ok_or("admin access is not configured.")?;
        if password.is_empty() || password.len() > 1024 {
            return Err("incorrect admin password.".into());
        }
        {
            let mut attempts = self.attempts.lock().map_err(|_| unavailable())?;
            while attempts
                .front()
                .is_some_and(|at| now.saturating_duration_since(*at) >= Duration::from_secs(60))
            {
                attempts.pop_front();
            }
            if attempts.len() >= 20 {
                return Err("too many admin login attempts. try again in a minute.".into());
            }
            attempts.push_back(now);
        }
        if self
            .verifying
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_err()
        {
            return Err("another admin login is being checked. try again shortly.".into());
        }
        let _verification = Verification(&self.verifying);
        let hash = PasswordHash::new(encoded).map_err(|_| unavailable())?;
        Argon2::default()
            .verify_password(password.as_bytes(), &hash)
            .map_err(|_| juniper::FieldError::from("incorrect admin password."))?;
        let token = Token(URL_SAFE_NO_PAD.encode(rand::random::<[u8; 32]>()));
        let mut sessions = self.sessions.lock().map_err(|_| unavailable())?;
        sessions.retain(|_, expires| *expires > now);
        if let Some(previous) = previous {
            sessions.remove(previous);
        }
        if sessions.len() >= MAX_SESSIONS {
            return Err("too many admin sessions. log out of another browser or wait for a session to expire.".into());
        }
        sessions.insert(token.clone(), now + SESSION_LIFETIME);
        Ok(token)
    }

    pub fn logout(&self, token: Option<&Token>) -> FieldResult<()> {
        let mut sessions = self.sessions.lock().map_err(|_| unavailable())?;
        if let Some(token) = token {
            sessions.remove(token);
        }
        Ok(())
    }
}

struct Verification<'a>(&'a AtomicBool);
impl Drop for Verification<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::Release);
    }
}

fn unavailable() -> juniper::FieldError {
    server_log::internal_error("admin authentication is unavailable.")
}
fn invalid_hash() -> io::Error {
    io::Error::new(
        io::ErrorKind::InvalidInput,
        "FIGHTLINES_ADMIN_PASSWORD_HASH must be an Argon2id v19 hash (memory 19456–65536 KiB, iterations 2–5, parallelism 1). use --hash-admin-password.",
    )
}

pub fn hash_password(password: &str) -> io::Result<String> {
    if password.len() < 15 || password.len() > 1024 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "use an admin password between 15 and 1024 bytes.",
        ));
    }
    let salt = SaltString::encode_b64(&rand::random::<[u8; 16]>())
        .map_err(|error| io::Error::other(error.to_string()))?;
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|hash| hash.to_string())
        .map_err(|error| io::Error::other(error.to_string()))
}

pub fn password_command() -> io::Result<()> {
    let password = rpassword::prompt_password("admin password: ")?;
    let confirmation = rpassword::prompt_password("confirm password: ")?;
    if password != confirmation {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "passwords did not match.",
        ));
    }
    println!("{}", hash_password(&password)?);
    Ok(())
}

impl Token {
    pub fn from_request(request: &HttpRequest) -> Option<Self> {
        request
            .cookie(COOKIE)
            .filter(|cookie| cookie.value().len() == 43)
            .map(|cookie| Self(cookie.value().to_owned()))
    }
}

impl CookieChange {
    pub fn cookie(&self, environment: Environment) -> Cookie<'static> {
        let (value, age) = match self {
            Self::Set(token) => (token.0.clone(), SESSION_LIFETIME.as_secs() as i64),
            Self::Remove => (String::new(), 0),
        };
        Cookie::build(COOKIE, value)
            .path("/")
            .http_only(true)
            .secure(environment == Environment::Production)
            .same_site(SameSite::Strict)
            .max_age(actix_web::cookie::time::Duration::seconds(age))
            .finish()
    }
}

/// Authenticated operations require a same-origin POST, including login/logout.
/// Host comes from the direct HTTP request; never trust a supplied forwarding host.
pub fn same_origin(request: &HttpRequest, environment: Environment) -> bool {
    let scheme = if environment == Environment::Production {
        "https"
    } else {
        "http"
    };
    let host = request
        .headers()
        .get("host")
        .and_then(|value| value.to_str().ok());
    let origin = request
        .headers()
        .get("origin")
        .and_then(|value| value.to_str().ok());
    match (host, origin) {
        (Some(host), Some(origin)) => origin == format!("{scheme}://{host}"),
        _ => false,
    }
}
