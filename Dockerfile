FROM nvidia/cuda:12.6.0-devel-ubuntu22.04 AS builder

WORKDIR /src
COPY src ./src
COPY Makefile .

RUN apt-get update && apt-get install -y --no-install-recommends make g++ libyaml-cpp-dev && make

FROM nvidia/cuda:12.6.0-base-ubuntu22.04

WORKDIR /app
COPY --from=builder /src/build/gpu-stressor /app/gpu-stressor

ENTRYPOINT ["/app/gpu-stressor"]
