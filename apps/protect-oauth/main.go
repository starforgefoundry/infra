package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/sessions"
	"github.com/gorilla/websocket"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

const sessionName = "nvr-session"
const allowedDomain = "starforgefoundry.com"

var (
	oauthConfig *oauth2.Config
	store       *sessions.CookieStore

	unifiMu       sync.RWMutex
	unifiCookies  []*http.Cookie
	unifiClient   *http.Client
	unifiHost     string
	unifiUsername string
	unifiPassword string
)

func main() {
	clientID := mustEnv("GOOGLE_CLIENT_ID")
	clientSecret := mustEnv("GOOGLE_CLIENT_SECRET")
	sessionSecret := mustEnv("SESSION_SECRET")
	redirectURL := mustEnv("REDIRECT_URL") // e.g. https://nvr.starforgefoundry.com/auth/callback

	unifiHost = mustEnv("UNIFI_HOST") // e.g. https://10.0.50.244
	unifiUsername = mustEnv("UNIFI_USERNAME")
	unifiPassword = mustEnv("UNIFI_PASSWORD")

	log.Printf("Access restricted to @%s accounts", allowedDomain)

	oauthConfig = &oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		RedirectURL:  redirectURL,
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

	unifiClient = &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		},
		Timeout: 30 * time.Second,
	}

	if err := loginToUnifi(); err != nil {
		log.Fatalf("Initial UniFi login failed: %v", err)
	}

	go func() {
		for range time.Tick(6 * time.Hour) {
			if err := loginToUnifi(); err != nil {
				log.Printf("UniFi session refresh failed: %v", err)
			}
		}
	}()

	mux := http.NewServeMux()
	mux.HandleFunc("/auth/login", handleLogin)
	mux.HandleFunc("/auth/callback", handleCallback)
	mux.HandleFunc("/auth/logout", handleLogout)
	mux.HandleFunc("/", requireAuth(handleProxy))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func mustEnv(key string) string {
	v := os.Getenv(key)
	if v == "" {
		log.Fatalf("Required env var %q is not set", key)
	}
	return v
}

// loginToUnifi authenticates with the local UniFi Protect instance and caches
// the session cookies. It is safe to call concurrently.
func loginToUnifi() error {
	body, _ := json.Marshal(map[string]string{
		"username": unifiUsername,
		"password": unifiPassword,
	})

	req, err := http.NewRequest(http.MethodPost, unifiHost+"/api/auth/login", bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("build login request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := unifiClient.Do(req)
	if err != nil {
		return fmt.Errorf("do login request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("UniFi login returned %d", resp.StatusCode)
	}

	cookies := resp.Cookies()
	unifiMu.Lock()
	unifiCookies = cookies
	unifiMu.Unlock()

	log.Printf("UniFi session refreshed (%d cookies)", len(cookies))
	return nil
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	state := randomHex(16)
	sess, _ := store.Get(r, sessionName)
	sess.Values["oauth_state"] = state
	// Save the original destination so we can redirect after login.
	if dest := r.URL.Query().Get("next"); dest != "" {
		sess.Values["post_login_redirect"] = dest
	}
	if err := sess.Save(r, w); err != nil {
		http.Error(w, "Session error", http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, oauthConfig.AuthCodeURL(state), http.StatusFound)
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

	sess.Values["authenticated"] = true
	sess.Values["email"] = email

	redirect := "/"
	if dest, ok := sess.Values["post_login_redirect"].(string); ok && dest != "" {
		redirect = dest
		delete(sess.Values, "post_login_redirect")
	}

	if err := sess.Save(r, w); err != nil {
		http.Error(w, "Session error", http.StatusInternalServerError)
		return
	}

	log.Printf("User %s authenticated", email)
	http.Redirect(w, r, redirect, http.StatusFound)
}

func handleLogout(w http.ResponseWriter, r *http.Request) {
	sess, _ := store.Get(r, sessionName)
	sess.Options.MaxAge = -1
	sess.Save(r, w)
	http.Redirect(w, r, "/auth/login", http.StatusFound)
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
	if info.Email == "" {
		return "", fmt.Errorf("empty email in userinfo response")
	}
	return info.Email, nil
}

func requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		sess, _ := store.Get(r, sessionName)
		if auth, ok := sess.Values["authenticated"].(bool); !ok || !auth {
			loginURL := "/auth/login"
			if dest := r.URL.RequestURI(); dest != "/" {
				loginURL += "?next=" + url.QueryEscape(dest)
			}
			http.Redirect(w, r, loginURL, http.StatusFound)
			return
		}
		next(w, r)
	}
}

// injectUnifiCookies replaces the request's Cookie header with the cached
// UniFi session cookies.
func injectUnifiCookies(r *http.Request) {
	r.Header.Del("Cookie")
	unifiMu.RLock()
	for _, c := range unifiCookies {
		r.AddCookie(c)
	}
	unifiMu.RUnlock()
}

func handleProxy(w http.ResponseWriter, r *http.Request) {
	// WebSocket upgrade requests must be tunnelled at the TCP level; the
	// standard ReverseProxy only handles regular HTTP.
	if strings.EqualFold(r.Header.Get("Upgrade"), "websocket") {
		proxyWebSocket(w, r)
		return
	}

	target, err := url.Parse(unifiHost)
	if err != nil {
		http.Error(w, "Bad gateway", http.StatusBadGateway)
		return
	}

	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.Transport = &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}

	injectUnifiCookies(r)
	r.Host = target.Host

	proxy.ModifyResponse = func(resp *http.Response) error {
		if resp.StatusCode == http.StatusUnauthorized {
			go func() {
				if err := loginToUnifi(); err != nil {
					log.Printf("Background UniFi re-login failed: %v", err)
				}
			}()
		}
		return nil
	}

	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		log.Printf("Proxy error: %v", err)
		http.Error(w, "Bad gateway", http.StatusBadGateway)
	}

	proxy.ServeHTTP(w, r)
}

var wsUpgrader = websocket.Upgrader{
	CheckOrigin:     func(r *http.Request) bool { return true },
	ReadBufferSize:  4096,
	WriteBufferSize: 4096,
}

var wsDialer = &websocket.Dialer{
	TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
}

// proxyWebSocket performs a proper WebSocket handshake on both sides and then
// forwards frames bidirectionally. This avoids hijacking issues when running
// behind a TLS-terminating proxy like Traefik.
func proxyWebSocket(w http.ResponseWriter, r *http.Request) {
	target, _ := url.Parse(unifiHost)

	// Build upstream WebSocket URL (wss since unifiHost is https).
	upstreamURL := *r.URL
	upstreamURL.Scheme = "wss"
	upstreamURL.Host = target.Host

	// Build request headers for the upstream — inject UniFi cookies and
	// forward any subprotocol the client requested.
	upstreamHeader := http.Header{}
	unifiMu.RLock()
	cookieParts := make([]string, 0, len(unifiCookies))
	for _, c := range unifiCookies {
		cookieParts = append(cookieParts, c.Name+"="+c.Value)
	}
	unifiMu.RUnlock()
	if len(cookieParts) > 0 {
		upstreamHeader.Set("Cookie", strings.Join(cookieParts, "; "))
	}
	if proto := r.Header.Get("Sec-Websocket-Protocol"); proto != "" {
		upstreamHeader.Set("Sec-Websocket-Protocol", proto)
	}

	upstreamWS, upstreamResp, err := wsDialer.Dial(upstreamURL.String(), upstreamHeader)
	if err != nil {
		log.Printf("WebSocket upstream dial failed (%s): %v", upstreamURL.String(), err)
		http.Error(w, "Bad gateway", http.StatusBadGateway)
		return
	}
	defer upstreamWS.Close()

	// Echo the subprotocol selected by the upstream back to the client.
	var responseHeader http.Header
	if proto := upstreamResp.Header.Get("Sec-Websocket-Protocol"); proto != "" {
		responseHeader = http.Header{"Sec-Websocket-Protocol": []string{proto}}
	}

	clientWS, err := wsUpgrader.Upgrade(w, r, responseHeader)
	if err != nil {
		log.Printf("WebSocket client upgrade failed: %v", err)
		return
	}
	defer clientWS.Close()

	done := make(chan struct{}, 2)

	forward := func(dst, src *websocket.Conn, label string) {
		defer func() { done <- struct{}{} }()
		for {
			mt, msg, err := src.ReadMessage()
			if err != nil {
				if !websocket.IsCloseError(err, websocket.CloseNormalClosure, websocket.CloseGoingAway, websocket.CloseNoStatusReceived) {
					log.Printf("WebSocket %s read error: %v", label, err)
				}
				// Propagate close to the other side.
				dst.WriteMessage(websocket.CloseMessage, websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
				return
			}
			if err := dst.WriteMessage(mt, msg); err != nil {
				log.Printf("WebSocket %s write error: %v", label, err)
				return
			}
		}
	}

	go forward(upstreamWS, clientWS, "client->upstream")
	go forward(clientWS, upstreamWS, "upstream->client")
	<-done
}

func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}
