all: rubydev-jammy

rubydev-bionic: Dockerfile.bionic
	docker build -f Dockerfile.bionic . -t rubydev:bionic

rubydev-focal: Dockerfile.focal
	docker build -f Dockerfile.focal . -t rubydev:focal

rubydev-jammy: Dockerfile.jammy
	docker build -f Dockerfile.jammy . -t rubydev:jammy
