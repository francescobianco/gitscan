
.PHONY: build release run clean push

build:
	mush build

release:
	mush build --release

run:
	mush run

clean:
	rm -rf target/

push:
	@git config credential.helper 'cache --timeout=3600'
	@git add .
	@git commit -m "update"
	@git push