# ClusterFuzzLite build image for the provider-response fuzzer
# (tests/fuzz/fuzz_provider_responses.py). The base image ships atheris.
FROM gcr.io/oss-fuzz-base/base-builder-python@sha256:21f6fab17ace4dc76e1c56de91ee95d3d03da021df94b41056ba036f6c6f55e9
# The adapters run jq at fuzz time and the runner image has none, so the
# fuzzer bundles the static jq release, verified by checksum.
ARG JQ_VERSION=1.8.2
ARG JQ_SHA256=b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f
RUN curl -fsSL -o /usr/local/bin/jq-static \
      "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-amd64" \
    && echo "${JQ_SHA256}  /usr/local/bin/jq-static" | sha256sum --check --strict \
    && chmod 755 /usr/local/bin/jq-static
COPY . $SRC/aioverviewcontrol
WORKDIR $SRC/aioverviewcontrol
COPY .clusterfuzzlite/build.sh $SRC/
