use actix_web::{
    HttpRequest,
    cookie::{Cookie, SameSite},
};

/// A browser identity credential. Possession authorizes that player's actions.
/// It is shared by tabs, is not an account, and is never included in JSON.
#[derive(Clone, PartialEq, Eq)]
pub struct SessionToken(String);

impl SessionToken {
    pub fn from_token(token: String) -> Self {
        Self(token)
    }

    pub fn from_request(request: &HttpRequest) -> Option<Self> {
        request
            .cookie("fightlines_session")
            .map(|cookie| Self(cookie.value().to_owned()))
    }

    pub fn cookie(&self) -> Cookie<'static> {
        Cookie::build("fightlines_session", self.0.clone())
            .path("/")
            .http_only(true)
            .same_site(SameSite::Lax)
            .max_age(actix_web::cookie::time::Duration::days(30))
            .finish()
    }
}
