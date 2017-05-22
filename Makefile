SHELL = /bin/sh
INSTALL = install
INSTALL_PROGRAM = ${INSTALL}

srcdir = .

prefix = /usr/local
exec_prefix = ${prefix}
bindir = ${exec_prefix}/bin
binprefix =

all: git-sync

.SUFFIXES:

check: all test-resources $(srcdir)/run-tests.sh
	$(SHELL) -eu $(srcdir)/run-tests.sh git-sync test-resources

clean:
	rm -f git-sync
	rm -rf test-resources
	rm -f test-results.log

git-sync: $(srcdir)/git-sync.sh
	rm -f $@
	sed '1s|^#!/bin/sh -eux$$|#!/bin/sh -eu|;2,$${/^[ ]*$$/d;/^[ ]*#/d;/ || exit 3$$/d;}' $(srcdir)/git-sync.sh > $@
	test "$$(sed -n '1p' $@)" = '#!/bin/sh -eu'
	chmod a+x $@

install: all
	$(INSTALL_PROGRAM) git-sync $(DESTDIR)$(bindir)/git-$(binprefix)sync

test-resources: $(srcdir)/generate-test-resources.sh
	rm -rf $@
	$(SHELL) -eu $(srcdir)/generate-test-resources.sh $@

uninstall:
	rm -f $(DESTDIR)$(bindir)/git-$(binprefix)sync

.PHONY: all check clean install uninstall
