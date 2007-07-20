# Makefile for dbahelper
# $Id$

DESTDIR=
BINDIR=$(DESTDIR)/opt/dbahelper
DOCDIR=$(DESTDIR)/usr/share/doc/dbahelper
#CONFDIR=$(DESTDIR)/etc
#MANDIR=$(DESTDIR)/usr/share/man
RPMROOT=$(DESTDIR)/usr/src/rpm
DEBLINK=$(DESTDIR)/usr/src/debian
INSTALL=install

install:
	mkdir -p $(DOCDIR)/html
	mkdir -p $(BINDIR)/rman
	$(INSTALL) -c -p -m 755 *.sh $(BINDIR)
	$(INSTALL) -c -p -m 750 globalconf $(BINDIR)
	$(INSTALL) -c -p -m 754 configure $(BINDIR)
	$(INSTALL) -c -p -m 644 rman/rman* $(BINDIR)/rman
	chmod 754 $(BINDIR)/rman/rman.sh
	$(INSTALL) -c -p -m 644 doc/html/* $(DOCDIR)/html
	$(INSTALL) -c -p -m 644 doc/history $(DOCDIR)
	$(INSTALL) -c -p -m 644 doc/LICENSE $(DOCDIR)
	$(INSTALL) -c -p -m 644 doc/readme.txt $(DOCDIR)
#	$(INSTALL) -c -m 644 man/*.5 $(MANDIR)/man5
#	$(INSTALL) -c -m 644 man/*.8 $(MANDIR)/man8
#	$(INSTALL) -c -m 644 tpl/* $(SPECDIR)
