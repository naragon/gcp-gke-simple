# Pin the builder digest; refresh deliberately with security updates.
FROM golang:1.27.2-alpine@sha256:f92b6ef800e499660581efdabdf25d9d817a9d124eaf900924f0504e7e27e12d AS build
WORKDIR /src
COPY go.mod main.go main_test.go ./
RUN go test ./... && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w -buildid=" -o /hello .

FROM scratch
COPY --from=build /hello /hello
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/hello"]
