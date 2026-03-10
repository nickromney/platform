ARG UBUNTU_VERSION=22.04
ARG LLAMA_CPP_REF=2b10b6267

FROM ubuntu:${UBUNTU_VERSION} AS build

ARG TARGETARCH
ARG LLAMA_CPP_REF

RUN apt-get update && \
    apt-get install -y build-essential git cmake libssl-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src

RUN git clone https://github.com/ggml-org/llama.cpp.git . && \
    git checkout "${LLAMA_CPP_REF}"

RUN if [ "${TARGETARCH}" = "amd64" ] || [ "${TARGETARCH}" = "arm64" ]; then \
      cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=OFF \
        -DLLAMA_BUILD_TESTS=OFF \
        -DGGML_BACKEND_DL=ON; \
    else \
      echo "Unsupported architecture: ${TARGETARCH}" >&2; \
      exit 1; \
    fi && \
    cmake --build build -j "$(nproc)" --target llama-server

RUN mkdir -p /out/lib && \
    find build -name "*.so*" -exec cp -P {} /out/lib \; && \
    cp build/bin/llama-server /out/llama-server

FROM ubuntu:${UBUNTU_VERSION}

RUN apt-get update && \
    apt-get install -y libgomp1 curl && \
    apt-get autoremove -y && \
    apt-get clean -y && \
    rm -rf /tmp/* /var/tmp/* /var/lib/apt/lists/*

COPY --from=build /out/lib/ /app/
COPY --from=build /out/llama-server /app/llama-server

ENV LLAMA_ARG_HOST=0.0.0.0

WORKDIR /app

HEALTHCHECK CMD ["curl", "-f", "http://localhost:8080/health"]

ENTRYPOINT ["/app/llama-server"]
