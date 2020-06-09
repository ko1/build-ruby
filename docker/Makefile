
all: rubydev-bionic

.gist:
	cp ~/.gist .

.gitconfig:
	cp ~/.gitconfig .


rubydev-bionic: .gist .gitconfig Dockerfile.bionic
	docker build -f Dockerfile.bionic . -t rubydev:bionic

rubydev-focal: .gist .gitconfig Dockerfile.focal
	docker build -f Dockerfile.focal . -t rubydev:focal

