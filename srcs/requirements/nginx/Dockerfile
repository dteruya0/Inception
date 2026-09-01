FROM debian:bookworm

ARG DOMAIN_NAME

RUN apt-get update && apt-get install -y --no-install-recommends \
        nginx openssl \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/inception.key \
        -out /etc/nginx/ssl/inception.crt \
        -subj "/C=BR/ST=SP/L=Sao Paulo/O=42/OU=42SP/CN=${DOMAIN_NAME}"

COPY conf/default.conf /etc/nginx/conf.d/default.conf
RUN rm -f /etc/nginx/sites-enabled/default

EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]
