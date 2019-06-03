FROM golang:1.12
WORKDIR /build
COPY go.* ./
RUN go mod download
COPY main.go ./
RUN GOOS=linux go build -o vault-iam-auth

FROM alpine:3.9
RUN apk add --update --no-cache ca-certificates jq
COPY --from=0 /build/vault-iam-auth /usr/local/bin
