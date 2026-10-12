package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHandler(t *testing.T) {
	for _, tc := range []struct {
		method, path string
		status       int
		body         string
	}{
		{"GET", "/", http.StatusOK, "Hello world!\n"},
		{"GET", "/healthz", http.StatusOK, ""},
		{"GET", "/missing", http.StatusNotFound, "404 page not found\n"},
		{"POST", "/", http.StatusMethodNotAllowed, "Method Not Allowed\n"},
	} {
		t.Run(tc.method+tc.path, func(t *testing.T) {
			w := httptest.NewRecorder()
			handler().ServeHTTP(w, httptest.NewRequest(tc.method, tc.path, nil))
			if w.Code != tc.status || w.Body.String() != tc.body {
				t.Fatalf("got (%d, %q), want (%d, %q)", w.Code, w.Body.String(), tc.status, tc.body)
			}
		})
	}
}
