.PHONY: build app run install clean

build:
	swift build

app:
	scripts/build-app.sh release

run: app
	open build/CatIsNotHelper.app

install: app
	rm -rf /Applications/CatIsNotHelper.app
	cp -R build/CatIsNotHelper.app /Applications/CatIsNotHelper.app
	@echo "Установлено в /Applications/CatIsNotHelper.app"

clean:
	rm -rf .build build
