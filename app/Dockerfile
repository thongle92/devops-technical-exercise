FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY go.mod ./
COPY main.go ./
COPY internal ./internal
RUN CGO_ENABLED=0 go build -o /greeter .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /greeter /greeter
EXPOSE 8080
ENTRYPOINT ["/greeter"]

