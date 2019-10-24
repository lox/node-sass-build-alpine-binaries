#!/bin/bash
set -euo pipefail

node_sass_version=4.13.0
node_versions=( 6 8 10 11 12 13 )
image_name="node-sass-alpine-builder"

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
	local base_image_name="$1"
	local file="$2"

	echo "Generating $file"
	cat <<- EOF > $file
	FROM ${base_image_name}
	ARG NODE_SASS_VERSION
	RUN apk add --no-cache python=2.7.14-r0 git-perl bash make gcc g++
	RUN rm /bin/sh && ln -s /bin/bash /bin/sh
	WORKDIR /node-sass
	COPY ./node-sass/package.json /node-sass/package.json
	RUN npm install --verbose
	COPY ./node-sass /node-sass/
	EOF
}

build_docker_image() {
	base_image_name="node:${major_node_version?need major node version}-alpine"
	dockerfile "${base_image_name}" "Dockerfile.${docker_image_name?need docker image name}"
	echo "Preparing Docker image \"${docker_image_name}\" based on \"${base_image_name}\""
	docker build --tag "${docker_image_name}" -f "Dockerfile.${docker_image_name}" \
		--build-arg NODE_SASS_VERSION=${node_sass_version} .
	rm "Dockerfile.${docker_image_name}"
}

inside_node_version() {
	if ! running_node_version=$(docker run --rm "${docker_image_name}" node --version) ; then
		echo "failed to get node version"
		exit 1
	fi
}

run_inside_container() {
	local volumes=(
		"$PWD/node-sass:/node-sass"
		"/node-sass/node_modules"
		"$PWD/build/${running_node_version?need running node version}:/build"
	)
	docker run \
		${volumes[@]/#/-v } \
		-it --rm "${docker_image_name?need docker image name}" "$@"
}

build_node_sass() {
	inside_node_version
	echo "Building node-sass ${node_sass_version} for node ${running_node_version} using \"${docker_image_name}\""
	run_inside_container bash -c "node scripts/build.js -f --verbose && cp -a vendor/* /build"
}

rename_build_files() {
	find build -type f -name 'binding.node' | while read FILE ; do
		mv "${FILE}" $(sed -e 's#linux-x64#linux_musl-x64#' <<< "$FILE" | sed -e 's#/binding#_binding#')
		rmdir $(dirname $FILE)
	done
}

## Main
## ----------------

## Output format should be like
# * build/v4.0.0
# * build/v4.0.0/linux_musl-x64-42_binding.node

checkout_source "$node_sass_version"

for major_node_version in "${node_versions[@]}" ; do
	docker_image_name="${image_name}:${major_node_version}"
	build_docker_image "${major_node_version}"
	build_node_sass
done

rename_build_files
