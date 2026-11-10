HELPINDEXES=$(addsuffix Help.helpindex, $(wildcard *.lproj/Help/))
SUBMODULES=../Sparkle/Sparkle ../svgcleaner/src

.DELETE_ON_ERROR:

build: all

all: $(SUBMODULES) pngout helpindexes

$(SUBMODULES): ../.gitmodules
	../scripts/fetch-submodule $(shell dirname $@) && touch $@

pngout-20230322-mac.zip:
	curl -fLO https://www.jonof.id.au/files/kenutils/pngout-20230322-mac.zip

pngout: pngout-20230322-mac.zip Makefile
	unzip -p pngout-20230322-mac.zip pngout-20230322-mac/pngout > pngout.universal
	lipo -thin arm64 pngout.universal -output pngout
	rm pngout.universal
	chmod a+rx pngout
	codesign -s "$(if $(EXPANDED_CODE_SIGN_IDENTITY),$(EXPANDED_CODE_SIGN_IDENTITY),-)" ./pngout --force

clean:
	-rm -rf pngout pngout.universal pngout-20230322-mac.zip

install:

helpindexes:: $(HELPINDEXES)

%/Help.helpindex: %/index.html %/prefs.html
	./makehelp.sh $(patsubst %.lproj/Help/Help.helpindex,%,$@)

.PHONY: build all install clean
