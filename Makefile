SUBDIRS =
DESTDIR =
UBINDIR ?= /usr/bin
LIBDIR ?= /usr/lib
SBINDIR ?= /sbin
USBINDIR ?= /usr/sbin
BINDIR ?= /bin
LIBEXECDIR ?= /usr/libexec
SYSCONFDIR ?= /etc

all:
	for d in $(SUBDIRS); do $(MAKE) -C $$d; done

clean:
	for d in $(SUBDIRS); do $(MAKE) -C $$d clean; done

install:
	for d in $(SUBDIRS); do $(MAKE) -C $$d install; done

	install -d $(DESTDIR)/$(SBINDIR)
	install -d $(DESTDIR)/$(BINDIR)
	install -m 0755 *-functions.sh $(DESTDIR)/$(SBINDIR)/

	install -d $(DESTDIR)/$(UBINDIR)
	install -m 0755 sark-* $(DESTDIR)/$(UBINDIR)/

.PHONY: tests
tests:
	@tests/run_tests.sh
