package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log"
	"net/http"
	"net/url"
	"os"
	"strings"

	"github.com/gorilla/sessions"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

const sessionName = "frigate-oauth"
const allowedDomain = "starforgefoundry.com"

var (
	oauthConfig *oauth2.Config
	store       *sessions.CookieStore
)

func main() {
	clientID := mustEnv("GOOGLE_CLIENT_ID")
	clientSecret := mustEnv("GOOGLE_CLIENT_SECRET")
	sessionSecret := mustEnv("SESSION_SECRET")
	callbackURL := mustEnv("CALLBACK_URL") // e.g. https://cam.starforgefoundry.com/_oauth/callback

	oauthConfig = &oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		RedirectURL:  callbackURL,
		Scopes:       []string{"https://www.googleapis.com/auth/userinfo.email"},
		Endpoint:     google.Endpoint,
	}

	store = sessions.NewCookieStore([]byte(sessionSecret))
	store.Options = &sessions.Options{
		Path:     "/",
		MaxAge:   86400 * 30, // 30 days
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteLaxMode,
	}

	log.Printf("frigate-oauth listening on :4181")
	log.Fatal(http.ListenAndServe(":4181", http.HandlerFunc(handleForwardAuth)))
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("Required env var %q is not set", key)
	}
	return v
}

// handleForwardAuth is the single entrypoint called by Traefik's forwardauth
// for every request. We dispatch based on X-Forwarded-Uri to handle the OAuth
// callback and logout within the forwardauth flow itself.
func handleForwardAuth(w http.ResponseWriter, r *http.Request) {
	forwardedURI := r.Header.Get("X-Forwarded-Uri")

	switch {
	case strings.HasPrefix(forwardedURI, "/_oauth/callback"):
		handleCallback(w, r, forwardedURI)
	case strings.HasPrefix(forwardedURI, "/_oauth/logout"):
		handleLogout(w, r)
	default:
		handleAuth(w, r)
	}
}

// handleAuth checks the session. If authenticated, returns 200 with headers.
// Otherwise, redirects to Google OAuth.
func handleAuth(w http.ResponseWriter, r *http.Request) {
	sess, _ := store.Get(r, sessionName)

	if email, ok := sess.Values["email"].(string); ok && email != "" {
		w.Header().Set("X-Forwarded-User", email)
		w.Header().Set("X-Forwarded-Groups", roleForUser(email))
		w.WriteHeader(http.StatusOK)
		return
	}

	state := randomHex(16)
	sess.Values["oauth_state"] = state
	sess.Values["redirect_url"] = buildOriginalURL(r)

	if err := sess.Save(r, w); err != nil {
		http.Error(w, "Session error", http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, oauthConfig.AuthCodeURL(state, oauth2.SetAuthURLParam("prompt", "select_account")), http.StatusTemporaryRedirect)
}

// handleCallback processes the OAuth callback. The query parameters (code, state)
// are on X-Forwarded-Uri since Traefik forwards the original URI as a header.
func handleCallback(w http.ResponseWriter, r *http.Request, forwardedURI string) {
	sess, _ := store.Get(r, sessionName)

	// Parse query params from the forwarded URI (not r.URL, which is the
	// forwardauth request URL).
	parsed, err := url.Parse(forwardedURI)
	if err != nil {
		http.Error(w, "Bad callback URI", http.StatusBadRequest)
		return
	}
	query := parsed.Query()

	expectedState, _ := sess.Values["oauth_state"].(string)
	if expectedState == "" || query.Get("state") != expectedState {
		http.Error(w, "Invalid OAuth state", http.StatusBadRequest)
		return
	}
	delete(sess.Values, "oauth_state")

	token, err := oauthConfig.Exchange(context.Background(), query.Get("code"))
	if err != nil {
		log.Printf("OAuth token exchange error: %v", err)
		http.Error(w, "Authentication failed", http.StatusInternalServerError)
		return
	}

	email, err := fetchGoogleEmail(token)
	if err != nil {
		log.Printf("Failed to fetch Google email: %v", err)
		http.Error(w, "Failed to retrieve user info", http.StatusInternalServerError)
		return
	}

	email = strings.ToLower(email)

	if !strings.HasSuffix(email, "@"+allowedDomain) {
		log.Printf("Access denied for %s (not a @%s account)", email, allowedDomain)
		http.Error(w, "Access denied: a @"+allowedDomain+" Google account is required", http.StatusForbidden)
		return
	}

	sess.Values["email"] = email

	redirect := "/"
	if dest, ok := sess.Values["redirect_url"].(string); ok && dest != "" {
		redirect = dest
		delete(sess.Values, "redirect_url")
	}

	if err := sess.Save(r, w); err != nil {
		http.Error(w, "Session error", http.StatusInternalServerError)
		return
	}

	log.Printf("User %s authenticated (role: %s)", email, roleForUser(email))
	http.Redirect(w, r, redirect, http.StatusFound)
}

func handleLogout(w http.ResponseWriter, r *http.Request) {
	sess, _ := store.Get(r, sessionName)
	sess.Options.MaxAge = -1
	sess.Save(r, w)
	http.Redirect(w, r, "/", http.StatusFound)
}

func fetchGoogleEmail(token *oauth2.Token) (string, error) {
	client := oauthConfig.Client(context.Background(), token)
	resp, err := client.Get("https://www.googleapis.com/oauth2/v2/userinfo")
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	var info struct {
		Email string `json:"email"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&info); err != nil {
		return "", err
	}
	return info.Email, nil
}

func roleForUser(email string) string {
	if email == "bwees@starforgefoundry.com" {
		return "admin"
	}
	return "viewer"
}

// buildOriginalURL reconstructs the URL the user originally requested,
// using the X-Forwarded-* headers set by Traefik.
func buildOriginalURL(r *http.Request) string {
	scheme := r.Header.Get("X-Forwarded-Proto")
	if scheme == "" {
		scheme = "https"
	}
	host := r.Header.Get("X-Forwarded-Host")
	if host == "" {
		host = r.Host
	}
	uri := r.Header.Get("X-Forwarded-Uri")
	if uri == "" {
		uri = r.URL.RequestURI()
	}

	u := &url.URL{
		Scheme: scheme,
		Host:   host,
		Path:   uri,
	}
	return u.String()
}

func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}
