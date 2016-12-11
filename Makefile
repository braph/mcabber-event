PREFIX = /usr

build:


install:
	install -m 0755 mcabber-event.pl $(PREFIX)/bin
	install -d $(PREFIX)/share/doc/mcabber-event
	install -m 0644 mcabber-event.rc $(PREFIX)/share/doc/mcabber-event
