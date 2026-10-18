.PHONY: build app install run clean

build:
	swift build

app:
	./Scripts/build-app.sh

install:
	./Scripts/install.sh

run: app
	open build/ConvertDock.app

clean:
	rm -rf .build build
