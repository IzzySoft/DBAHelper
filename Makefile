# Makefile for dbahelper
# $Id$

DESTDIR=
prefix=/usr/local
datarootdir=$(prefix)/share
fdatadir=$(datarootdir)/dbahelper
datadir=$(DESTDIR)$(fdatadir)
docdir=$(DESTDIR)$(datarootdir)/doc/dbahelper
sysconfdir=$(DESTDIR)/etc
bindir=$(DESTDIR)$(prefix)/bin
INSTALL=install
INSTALL_DATA=$(INSTALL) -m 644

install: installdirs
	$(INSTALL) -c -p -m 755 *.sh $(datadir)
	$(INSTALL) -c -p -m 750 globalconf $(datadir)
	$(INSTALL) -c -p -m 754 configure $(datadir)
	$(INSTALL_DATA) -c -p rman/rmanrc $(sysconfdir)
	echo "BINDIR=$(fdatadir)/rman">> $(sysconfdir)/rmanrc
	$(INSTALL) -c -p -m 755 rman/rmanw $(bindir)
	$(INSTALL_DATA) -c -p rman/rman* $(datadir)/rman
	$(INSTALL_DATA) -c -p rman/mods/* $(datadir)/rman/mods
	chmod 754 $(datadir)/rman/rman.sh
	$(INSTALL_DATA) -c -p doc/html/* $(docdir)/html
	$(INSTALL_DATA) -c -p doc/history $(docdir)
	$(INSTALL_DATA) -c -p doc/LICENSE $(docdir)
	$(INSTALL_DATA) -c -p doc/readme.* $(docdir)
	$(INSTALL_DATA) -c -p doc/install.txt $(docdir)

installdirs:
	mkdir -p $(docdir)/html
	mkdir -p $(datadir)/rman/mods

uninstall:
	rm -rf $(datadir)
	rm -rf $(docdir)
	rm -f $(bindir)/rmanw

purge: uninstall
	rm -f $(sysconfdir)/rmanrc

