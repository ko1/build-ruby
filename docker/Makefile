
all: rubydev-bionic

.gist:
	cp ~/.gist .

.gitconfig:
	cp ~/.gitconfig .

rubydev-bionic: .gist .gitconfig
	docker build -f Dockerfile.bionic . -t rubydev:bionic

