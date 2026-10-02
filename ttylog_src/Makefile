# Installs the ttylog pipeline and the `acsle` CLI.
# This only places files; it never touches sshd. Use install.sh for a full setup.
#
#   make install                      # into /usr
#   make install DESTDIR=/tmp/stage   # for image builds / packaging
#   make check                        # syntax-check every script

VERSION ?= 0.1.0
PREFIX  ?= /usr
LIBDIR  ?= $(PREFIX)/lib/acsle
BINDIR  ?= $(PREFIX)/bin
CONFDIR ?= /etc/acsle
LOGDIRS ?= /var/log/ttylog /var/log/analyze_cont

# install.sh goes in too, so package hooks can run its --sshd-only step
LIB_EXEC = script.sh start_ttylog.sh ttylog/ttylog analyze_continuous.py install.sh
LIB_DATA = milestones-lbl.pl

.PHONY: install uninstall check packages

install:
	install -d $(DESTDIR)$(LIBDIR) $(DESTDIR)$(BINDIR) $(DESTDIR)$(CONFDIR)
	for f in $(LIB_EXEC); do install -m 755 $$f $(DESTDIR)$(LIBDIR)/; done
	for f in $(LIB_DATA); do install -m 644 $$f $(DESTDIR)$(LIBDIR)/; done
	install -m 755 acsle $(DESTDIR)$(BINDIR)/acsle
	@# Keep an existing config; write the new defaults alongside it
	if [ -e $(DESTDIR)$(CONFDIR)/acsle.conf ]; then \
		install -m 644 acsle.conf $(DESTDIR)$(CONFDIR)/acsle.conf.new; \
	else \
		sed 's|^ACSLE_LIBDIR=.*|ACSLE_LIBDIR=$(LIBDIR)|' acsle.conf > $(DESTDIR)$(CONFDIR)/acsle.conf; \
		chmod 644 $(DESTDIR)$(CONFDIR)/acsle.conf; \
	fi
	for d in $(LOGDIRS); do install -d -m 755 $(DESTDIR)$$d; done

uninstall:
	rm -rf $(DESTDIR)$(LIBDIR)
	rm -f $(DESTDIR)$(BINDIR)/acsle
	rm -f $(DESTDIR)$(CONFDIR)/acsle.conf.new

check:
	bash -n start_ttylog.sh
	bash -n script.sh
	sh -n install.sh
	perl -c ttylog/ttylog
	python3 -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' analyze_continuous.py acsle

# Needs nfpm (https://nfpm.goreleaser.com). Output goes to dist/
packages:
	rm -rf build && $(MAKE) install DESTDIR=$(CURDIR)/build
	mkdir -p dist
	for p in deb rpm apk archlinux; do VERSION=$(VERSION) nfpm package -f packaging/nfpm.yaml -p $$p -t dist/; done
