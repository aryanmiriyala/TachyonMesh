package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"
)

type ProcessResponse struct {
	Status    string      `json:"status"`
	Processed bool        `json:"processed"`
	Inventory interface{} `json:"inventory"`
}

type HealthResponse struct {
	Status string `json:"status"`
	Uptime string `json:"uptime"`
}

var startTime time.Time

func init() {
	startTime = time.Now()
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(HealthResponse{
		Status: "ok",
		Uptime: time.Since(startTime).String(),
	})
}

func processHandler(w http.ResponseWriter, r *http.Request) {
	reqID := r.Header.Get("X-Request-Id")
	log.Printf("[Gateway] Processing request: %s", reqID)

	// Call downstream inventory service
	inventoryURL := os.Getenv("INVENTORY_URL")
	if inventoryURL == "" {
		inventoryURL = "http://inventory-service:8082/inventory"
	}

	client := &http.Client{Timeout: 5 * time.Second}
	req, err := http.NewRequest("GET", inventoryURL, nil)
	if err != nil {
		http.Error(w, "Failed to create request", http.StatusInternalServerError)
		return
	}

	// Propagate Trace Context and Request ID
	req.Header.Set("X-Request-Id", reqID)
	req.Header.Set("Traceparent", r.Header.Get("Traceparent"))

	resp, err := client.Do(req)
	if err != nil {
		log.Printf("[Gateway] Downstream error: %v", err)
		http.Error(w, "Inventory service unavailable", http.StatusServiceUnavailable)
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	var inventoryData interface{}
	json.Unmarshal(body, &inventoryData)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(ProcessResponse{
		Status:    "success",
		Processed: true,
		Inventory: inventoryData,
	})
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/api/process", processHandler)

	server := &http.Server{
		Addr:         fmt.Sprintf(":%s", port),
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  30 * time.Second,
	}

	go func() {
		log.Printf("Gateway service starting on :%s", port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	sig := <-quit
	log.Printf("Received signal %s, shutting down gracefully...", sig)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited cleanly")
}
