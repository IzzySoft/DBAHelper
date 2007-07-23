# Makefile for dbahelper
# $Id$

DESTDIR=
BINDIR=$(DESTDIR)/opt/dbahelper
DOCDIR=$(DESTDIR)/usr/share/doc/dbahelper
INSTALL=install
INSTALL_DATA=$(INSTALL) -m 644

install: installdirs
	$(INSTALL) -c -p -m 755 *.sh $(BINDIR)
	$(INSTALL) -c -p -m 750 globalconf $(BINDIR)
	$(INSTALL) -c -p -m 754 configure $(BINDIR)
	$(INSTALL_DATA) -c -p rman/rman* $(BINDIR)/rman
	chmod 754 $(BINDIR)/rman/rman.sh
	$(INSTALL_DATA) -c -p doc/html/* $(DOCDIR)/html
	$(INSTALL_DATA) -c -p doc/history $(DOCDIR)
	$(INSTALL_DATA) -c -p doc/LICENSE $(DOCDIR)
	$(INSTALL_DATA) -c -p doc/readme.txt $(DOCDIR)

installdirs:
	mkdir -p $(DOCDIR)/html
	mkdir -p $(BINDIR)/rman

uninstall:
	rm -rf $(BINDIR)
	rm -rf $(DOCDIR)
