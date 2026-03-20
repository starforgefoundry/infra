# Builder stage
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY main.go .

RUN go mod init app && go build -o main main.go

# Runner stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/main .
EXPOSE 8000

CMD ["./main"]