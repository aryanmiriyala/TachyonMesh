# -- Build stage --
FROM golang:1.22-alpine AS builder

WORKDIR /app

COPY go.mod ./
# No external dependencies, so no go.sum needed
RUN go mod download

COPY main.go ./

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /tachyon-gateway main.go

# -- Runtime stage --
FROM scratch

COPY --from=builder /tachyon-gateway /tachyon-gateway

EXPOSE 8081

ENTRYPOINT ["/tachyon-gateway"]
