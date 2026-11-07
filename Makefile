PREFIX ?= /usr
DESTDIR ?=

.PHONY: all build test clean install

all: build

build:
	go build -ldflags="-s -w" -o bin/asura-sysmon ./cmd/asura-sysmon

test:
	gofmt -l .
	go vet ./...
	go test -v -race ./...

install: build
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 bin/asura-sysmon $(DESTDIR)$(PREFIX)/bin/asura-sysmon
	install -d $(DESTDIR)$(PREFIX)/share/asura/sysmon
	cp -r ui/* $(DESTDIR)$(PREFIX)/share/asura/sysmon/
	install -d $(DESTDIR)$(PREFIX)/share/applications
	install -m 644 asura-sysmon.desktop $(DESTDIR)$(PREFIX)/share/applications/asura-sysmon.desktop

clean:
	rm -rf bin
