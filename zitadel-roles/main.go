package main

import (
	"bytes"
	"encoding/json"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"sync"
	"time"
	"strings"
)

var (
	ZITADEL_API   = os.Getenv("ZITADEL_INSTANCE")
	ZITADEL_TOKEN = os.Getenv("ZITADEL_TOKEN") 
	CACHE_TTL     = 3600 // seconds

	projectIDs = map[string]string{
		"cam.starforgefoundry.com":     "337742327613232742",
	}
)

type CacheEntry struct {
	Roles []string
	TS    time.Time
}

var cache = make(map[string]CacheEntry)
var cacheMu sync.RWMutex

// getCachedRoles returns cached roles if valid
func getCachedRoles(email string) ([]string, bool) {
	cacheMu.RLock()
	defer cacheMu.RUnlock()
	entry, ok := cache[email]
	if !ok || time.Since(entry.TS).Seconds() > float64(CACHE_TTL) {
		return nil, false
	}
	return entry.Roles, true
}

// setCachedRoles saves roles in cache
func setCachedRoles(email string, roles []string) {
	cacheMu.Lock()
	defer cacheMu.Unlock()
	cache[email] = CacheEntry{Roles: roles, TS: time.Now()}
}

// Zitadel API response structs
type EmailQuery struct {
	Email  string `json:"email"`
	Method string `json:"method"`
}

type Query struct {
	EmailQuery EmailQuery `json:"emailQuery"`
}

type SearchPayload struct {
	Query   map[string]interface{} `json:"query"`
	Queries []Query                `json:"queries"`
}

type ProjectGrant struct {
	ProjectID string   `json:"projectId"`
	RoleKeys  []string `json:"roleKeys"`
}

type SearchResult struct {
	Result []ProjectGrant `json:"result"`
}

// getRoles fetches roles for a user email and projectId
func getRoles(userEmail, projectId string) ([]string, error) {
	if roles, ok := getCachedRoles(userEmail); ok {
		return roles, nil
	}

	payload := SearchPayload{
		Query: map[string]interface{}{
			"offset": "0",
			"limit":  "100",
			"asc":    true,
		},
		Queries: []Query{
			{
				EmailQuery: EmailQuery{
					Email:  userEmail,
					Method: "TEXT_QUERY_METHOD_EQUALS",
				},
			},
		},
	}

	bodyBytes, _ := json.Marshal(payload)
	req, err := http.NewRequest("POST", ZITADEL_API+"/management/v1/users/grants/_search", bytes.NewBuffer(bodyBytes))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Authorization", "Bearer "+ZITADEL_TOKEN)

	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil, http.ErrNoLocation
	}

	respBody, _ := ioutil.ReadAll(resp.Body)
	var result SearchResult
	if err := json.Unmarshal(respBody, &result); err != nil {
		return nil, err
	}

	var roles []string
	for _, project := range result.Result {
		if project.ProjectID == projectId {
			roles = project.RoleKeys
			break
		}
	}

	setCachedRoles(userEmail, roles)
	return roles, nil
}

// handler for /auth
func authHandler(w http.ResponseWriter, r *http.Request) {
	userEmail := r.Header.Get("X-Forwarded-User")
	site := r.Header.Get("X-Forwarded-Host")

	if userEmail == "" {
		http.Error(w, "Missing X-Forwarded-User", http.StatusUnauthorized)
		return
	}

	projectId, ok := projectIDs[site]
	if !ok {
		http.Error(w, "Unknown site", http.StatusBadRequest)
		return
	}

	roles, err := getRoles(userEmail, projectId)
	if err != nil {
		http.Error(w, "User lookup failed", http.StatusUnauthorized)
		return
	}

	w.Header().Set("X-Forwarded-User", userEmail)
	if len(roles) > 0 {
		w.Header().Set("X-Forwarded-Groups", strings.Join(roles, ","))
	} else {
		w.Header().Set("X-Forwarded-Groups", "viewer")
	}

	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func main() {
	http.HandleFunc("/auth", authHandler)
	log.Println("Starting server on :8000")
	log.Fatal(http.ListenAndServe(":8000", nil))
}
