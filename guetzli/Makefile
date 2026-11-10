build: all

all: guetzli/guetzli

guetzli/guetzli: ../.gitmodules
	../scripts/fetch-submodule guetzli && touch guetzli/guetzli

.PHONY: build all install clean

