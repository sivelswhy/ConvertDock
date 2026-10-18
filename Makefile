.PHONY: build app install run logos clean

build:
	swift build

app:
	./Scripts/build-app.sh

install:
	./Scripts/install.sh

run: app
	open build/ConvertDock.app

logos:
	swift Scripts/generate-logos.swift Logos

clean:
	rm -rf .build build
