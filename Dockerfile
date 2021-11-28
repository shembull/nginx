FROM alpine:latest AS builder

RUN adduser -S nginx \
    && addgroup -S nginx

ENV PCRE_V=8.45
ENV ZLIB_V=1.2.11
ENV ZLIB_D=1211
ENV OPENSSL_V=1.1.1k
ENV NGINX_V=1.21.1

WORKDIR /build

# Build custom nginx server
RUN set -x \
    && apk update \
    && apk add curl tar git

RUN set -x \
    && cd /build \
    && curl https://netcologne.dl.sourceforge.net/project/pcre/pcre/8.45/pcre-8.45.tar.bz2 -o pcre.tar.bz2 \
    && tar -xf pcre.tar.bz2

RUN set -x \
    && git clone https://github.com/stnoonan/spnego-http-auth-nginx-module.git

RUN set -x \
    && git clone https://github.com/google/ngx_brotli.git \
    && cd ngx_brotli \
    && git submodule update --init

RUN set -x \
    && apk del --purge curl tar git

COPY . /build

RUN set -x \
    && apk update \
    && apk add curl tar make g++ krb5-dev linux-headers perl automake autoconf \
    && cd /build \
    && ./auto/configure --prefix=/usr/share/nginx \
        --sbin-path=/usr/sbin/nginx \
        --modules-path=/usr/lib/nginx/modules \
        --conf-path=/etc/nginx/nginx.conf \
        --error-log-path=/var/log/nginx/error.log \
        --http-log-path=/var/log/nginx/access.log \
        --pid-path=/run/nginx.pid \
        --lock-path=/var/lock/nginx.lock \
        --user=nginx \
        --group=nginx \
        --build=Alpine \
        --http-client-body-temp-path=/var/lib/nginx/body \
        --http-fastcgi-temp-path=/var/lib/nginx/fastcgi \
        --http-proxy-temp-path=/var/lib/nginx/proxy \
        --http-scgi-temp-path=/var/lib/nginx/scgi \
        --http-uwsgi-temp-path=/var/lib/nginx/uwsgi \
        --with-openssl=/build/modules/openssl \
        --with-openssl-opt=enable-ec_nistp_64_gcc_128 \
        --with-openssl-opt=no-nextprotoneg \
        --with-openssl-opt=no-weak-ssl-ciphers \
        --with-openssl-opt=no-ssl3 \
        --with-pcre=/build/pcre-$(echo $PCRE_V) \
        --with-pcre-jit \
        --with-zlib=/build/modules/zlib \
        --with-compat \
        --with-file-aio \
        --with-threads \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_dav_module \
        --with-http_flv_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_mp4_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_slice_module \
        --with-http_ssl_module \
        --with-http_sub_module \
        --with-http_stub_status_module \
        --with-http_v2_module \
        --with-http_secure_link_module \
        --with-mail \
        --with-mail_ssl_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-debug \
        --add-module=/build/spnego-http-auth-nginx-module \
        --add-module=/build/ngx_brotli \
        --with-cc-opt='-g -O2 -fPIE -fstack-protector-strong -Wformat -Werror=format-security -Wdate-time -D_FORTIFY_SOURCE=2' \
        --with-ld-opt='-Wl,-Bsymbolic-functions -fPIE -pie -Wl,-z,relro -Wl,-z,now' \
    && make \
    && make install \
    && mkdir -p /var/lib/nginx \
    && cd / \
    && rm -r /build \
    && apk del --purge curl tar make g++ linux-headers perl automake autoconf

FROM alpine:latest

COPY --from=builder /usr/sbin/nginx /usr/sbin/
COPY --from=builder /usr/share/nginx/html/* /usr/share/nginx/html/
COPY --from=builder /etc/nginx/* /etc/nginx/

RUN \
    apk update \
    # Bring in tzdata so users could set the timezones through the environment
    # variables
    && apk add --no-cache tzdata \
    \
    && apk add --no-cache \
    pcre \
    libgcc \
    krb5 \
    && addgroup -S nginx \
    && adduser -D -S -h /var/cache/nginx -s /sbin/nologin -G nginx nginx \
    && mkdir -p /var/lib/nginx \
    # forward request and error logs to docker log collector
    && mkdir -p /var/log/nginx \
    && mkdir -p /var/lib/nginx/body \
    && touch /var/log/nginx/access.log /var/log/nginx/error.log \
    && chown nginx: /var/log/nginx/access.log /var/log/nginx/error.log \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log

STOPSIGNAL SIGTERM

EXPOSE 80/tcp
EXPOSE 443/tcp

ENTRYPOINT ["/usr/sbin/nginx"]

CMD ["-g", "daemon off;"]
