# -- Build stage --
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /tachyon-inventory main.go

# -- Runtime stage --
FROM scratch
COPY --from=builder /tachyon-inventory /tachyon-inventory
EXPOSE 8082
ENTRYPOINT ["/tachyon-inventory"]
