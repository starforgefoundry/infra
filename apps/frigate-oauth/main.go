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

	mux := http.NewServeMux()
	mux.HandleFunc("/_oauth/callback", handleCallback)
	mux.HandleFunc("/_oauth/logout", handleLogout)
	mux.HandleFunc("/", handleAuth)

	log.Printf("frigate-oauth listening on :4181")
	log.Fatal(http.ListenAndServe(":4181", mux))
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("Required env var %q is not set", key)
	}
	return v
}

// handleAuth is the forwardauth endpoint. Traefik calls this on every request.
// If the user has a valid session, return 200 with user/group headers.
// Otherwise, redirect to Google OAuth.
func handleAuth(w http.ResponseWriter, r *http.Request) {
	sess, _ := store.Get(r, sessionName)

	if email, ok := sess.Values["email"].(string); ok && email != "" {
		w.Header().Set("X-Forwarded-User", email)
		w.Header().Set("X-Forwarded-Groups", roleForUser(email))
		w.WriteHeader(http.StatusOK)
		return
	}

	// Not authenticated — start OAuth flow.
	// Save the original URL so we can redirect back after login.
	state := randomHex(16)
	sess.Values["oauth_state"] = state

	// The X-Forwarded-* headers from Traefik tell us the original request URL.
	origURL := buildOriginalURL(r)
	sess.Values["redirect_url"] = origURL

	if err := sess.Save(r, w); err != nil {
		http.Error(w, "Session error", http.StatusInternalServerError)
		return
	}

	http.Redirect(w, r, oauthConfig.AuthCodeURL(state, oauth2.SetAuthURLParam("prompt", "select_account")), http.StatusTemporaryRedirect)
}

func handleCallback(w http.ResponseWriter, r *http.Request) {
	sess, _ := store.Get(r, sessionName)

	expectedState, _ := sess.Values["oauth_state"].(string)
	if expectedState == "" || r.URL.Query().Get("state") != expectedState {
		http.Error(w, "Invalid OAuth state", http.StatusBadRequest)
		return
	}
	delete(sess.Values, "oauth_state")

	token, err := oauthConfig.Exchange(context.Background(), r.URL.Query().Get("code"))
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
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("Logged out"))
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
		Scheme:   scheme,
		Host:     host,
		Path:     uri,
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
