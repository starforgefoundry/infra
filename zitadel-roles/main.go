package main

import (
	"log"
	"net/http"
)

// handler for /auth
func authHandler(w http.ResponseWriter, r *http.Request) {
	userEmail := r.Header.Get("X-Forwarded-User")

	if userEmail == "" {
		http.Error(w, "Missing X-Forwarded-User", http.StatusUnauthorized)
		return
	}

	w.Header().Set("X-Forwarded-User", userEmail)
	if userEmail == "bwees@starforgefoundry.com" {
		w.Header().Set("X-Forwarded-Groups", "admin")
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
