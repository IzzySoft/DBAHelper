# Makefile for dbahelper
# $Id$

DESTDIR=
prefix=/usr/local
BINDIR=$(DESTDIR)$(prefix)/dbahelper
datarootdir=$(DESTDIR)$(prefix)/share
datadir=$(datarootdir)
docdir=$(datarootdir)/doc/dbahelper
INSTALL=install
INSTALL_DATA=$(INSTALL) -m 644

install: installdirs
	$(INSTALL) -c -p -m 755 *.sh $(BINDIR)
	$(INSTALL) -c -p -m 750 globalconf $(BINDIR)
	$(INSTALL) -c -p -m 754 configure $(BINDIR)
	$(INSTALL_DATA) -c -p rman/rman* $(BINDIR)/rman
	chmod 754 $(BINDIR)/rman/rman.sh
	$(INSTALL_DATA) -c -p doc/html/* $(docdir)/html
	$(INSTALL_DATA) -c -p doc/history $(docdir)
	$(INSTALL_DATA) -c -p doc/LICENSE $(docdir)
	$(INSTALL_DATA) -c -p doc/readme.txt $(docdir)

installdirs:
	mkdir -p $(docdir)/html
	mkdir -p $(BINDIR)/rman

uninstall:
	rm -rf $(BINDIR)
	rm -rf $(docdir)
