# Makefile for dbahelper
# $Id$

DESTDIR=
prefix=/usr/local
datarootdir=$(DESTDIR)$(prefix)/share
datadir=$(datarootdir)/dbahelper
docdir=$(datarootdir)/doc/dbahelper
INSTALL=install
INSTALL_DATA=$(INSTALL) -m 644

install: installdirs
	$(INSTALL) -c -p -m 755 *.sh $(datadir)
	$(INSTALL) -c -p -m 750 globalconf $(datadir)
	$(INSTALL) -c -p -m 754 configure $(datadir)
	$(INSTALL_DATA) -c -p rman/rman* $(datadir)/rman
	chmod 754 $(datadir)/rman/rman.sh
	$(INSTALL_DATA) -c -p doc/html/* $(docdir)/html
	$(INSTALL_DATA) -c -p doc/history $(docdir)
	$(INSTALL_DATA) -c -p doc/LICENSE $(docdir)
	$(INSTALL_DATA) -c -p doc/readme.* $(docdir)
	$(INSTALL_DATA) -c -p doc/install.txt $(docdir)

installdirs:
	mkdir -p $(docdir)/html
	mkdir -p $(datadir)/rman

uninstall:
	rm -rf $(datadir)
	rm -rf $(docdir)
