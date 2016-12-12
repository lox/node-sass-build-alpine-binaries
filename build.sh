#!/bin/bash
set -euo pipefail

node_sass_version=3.7.0
node_versions=( 4 6 7 )
image_name=node-sass-alpine-builder

checkout_source() {
	local version="$1"
	echo "Checking out node-sass v${version}"
	[[ -d node-sass/.git ]] || git clone https://github.com/sass/node-sass --recursive
	(
	cd node-sass
	rm -rf vendor/
	git clean -f -d
	git checkout "v$version"
	git submodule update --init --recursive
	)
}

dockerfile() {
	local version="$1"
	local file="$2"

	echo "Generating $file"
	cat <<- EOF > $file
	FROM node:${version}-alpine
	ARG NODE_SASS_VERSION
	RUN apk add --no-cache python=2.7.12-r0 git-perl bash make gcc g++
	RUN rm /bin/sh && ln -s /bin/bash /bin/sh
	WORKDIR /node-sass
	COPY ./node-sass/package.json /node-sass/package.json
	RUN npm install --verbose
	COPY ./node-sass /node-sass
	EOF
}

build_docker_image() {
	local version="$1"
	dockerfile "$version" "Dockerfile.${version}"
	echo "Building $image_name:${version}"
	docker build --tag "$image_name:${version}" -f "Dockerfile.${version}" \
		--build-arg NODE_SASS_VERSION=${node_sass_version} .
	rm "Dockerfile.${version}"
}

build_node_sass() {
	local version="$1"
	local volumes=(
		"$PWD/node-sass:/node-sass"
		"$PWD/build/${version}:/build"
	)
	set -x
	docker run \
		${volumes[@]/#/-v } \
		-it --rm "$image_name:${version}" \
			bash -c "node scripts/build.js -f --verbose && cp -a vendor/* /build"
}

## Main
## ----------------

checkout_source "$node_sass_version"

for version in "${node_versions[@]}" ; do
	build_docker_image "$version"
	build_node_sass "$version"
done