.POSIX:
HARE = hare
HAREFLAGS = -lc -lsqlite3
HAREPATH = $(shell echo vendor/*/):$(shell hare version -vv 2>/dev/null | grep HAREPATH | cut -d= -f2)

all:
	HAREPATH=$(HAREPATH) $(HARE) build $(HAREFLAGS) .

.PHONY: all
