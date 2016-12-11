#!/bin/bash
set -euo pipefail

node_sass_version=3.7.0
node_versions=( 0.10 0.12 4 5 6 )
image_name=node-sass-alpine-builder

checkout_source() {
	local version="$1"
	echo "Checking out node-sass v${version}"
	[[ -d node-sass/.git ]] || git clone https://github.com/sass/node-sass --recursive
	(
	cd node-sass
	git clean -f -d
	git checkout "v$version"
	git submodule update --init --recursive
	)
}

build_docker_image() {
	local version="$1"
	echo "Building $image_name:${version}"
	docker build --tag "$image_name:${version}" - <<- EOF
	FROM mhart/alpine-node:${version}
	RUN apk add --no-cache python=2.7.12-r0 git-perl bash make gcc g++
	RUN rm /bin/sh && ln -s /bin/bash /bin/sh
	WORKDIR /node-sass
	EOF
}

build_node_sass() {
	local version="$1"
	set -x
	docker run \
		-v "$PWD/.npm:/root/.npm" \
		-v "$PWD/node-sass:/node-sass" \
		-v "$PWD/build/${version}:/node-sass/vendor" \
		-v "node_modules_${version}:/node-sass/node_modules" \
		--rm "$image_name:${version}" \
			bash -c "npm install --depth=1 && node scripts/build.js -f --verbose"
}

## Main
## ----------------

checkout_source "$node_sass_version"

for version in "${node_versions[@]}" ; do
	build_docker_image "$version"
	build_node_sass "$version"
	# docker run node-sass-binaries cat /node-sass/binaries.tar.gz > "binary-$i.tar.gz"
done