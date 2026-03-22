# Builder stage
FROM golang:1.25-alpine AS builder

WORKDIR /app
COPY main.go .

RUN go mod init app && go mod tidy && go build -o main main.go

# Runner stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/main .
EXPOSE 4181

CMD ["./main"]
