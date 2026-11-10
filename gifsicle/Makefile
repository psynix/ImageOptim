build: all

all: gifsicle/src/gifsicle.c

gifsicle/src/gifsicle.c: orig/src/gifsicle.c Makefile
	-rm -rf gifsicle
	cp -R orig gifsicle

orig/src/gifsicle.c: ../.gitmodules
	../scripts/fetch-submodule orig && touch orig/src/gifsicle.c

clean:
	-rm -rf patched gifsicle

.PHONY: build all install clean
