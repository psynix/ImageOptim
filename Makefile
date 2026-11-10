# Sparkle has its own settings, so override them for all subprojects.
XCODEBUILD = xcodebuild -project imageoptim/ImageOptim.xcodeproj -scheme ImageOptim -derivedDataPath imageoptim/build MACOSX_DEPLOYMENT_TARGET=12.0 ARCHS=arm64

.PHONY: build test prepare

build: prepare
	$(XCODEBUILD) -configuration Release CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO build

test: prepare
	$(XCODEBUILD) -configuration Debug CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO test
	$(MAKE) -C svgo test

# Materialize legacy generated sources before Xcode scans its build inputs.
prepare:
	git submodule update --init --recursive
	rustup target add aarch64-apple-darwin
	for directory in advpng gifsicle guetzli jpegoptim libjpeg libpng pngcrush pngquant zlib zopfli-png imageoptim svgo; do $(MAKE) -C $$directory all || exit $$?; done
