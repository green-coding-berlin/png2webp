FROM debian:bullseye-slim

RUN apt-get update && \
    apt-get install -y webp git bc && \
    rm -rf /var/lib/apt/lists/*

COPY png2webp.sh /usr/local/bin/png2webp.sh
RUN chmod +x /usr/local/bin/png2webp.sh

WORKDIR /data

ENTRYPOINT ["/usr/local/bin/png2webp.sh"]
