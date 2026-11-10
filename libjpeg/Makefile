build: all

all: src/jpeglib.h neon-compat.h

src/jpeglib.h: ../.gitmodules
	../scripts/fetch-submodule src && touch src/jpeglib.h

# Xcode 27's arm64 compiler provides all three intrinsics tested by upstream.
neon-compat.h: src/simd/arm/neon-compat.h.in
	sed 's/^#cmakedefine /#define /' $< > $@

.PHONY: build all install clean
