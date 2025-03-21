proxy_cache_path /cache/nginx levels=1:2 keys_zone=takahe:20m inactive=14d max_size=__CACHESIZE__;

upstream takahe {
    server "127.0.0.1:8001";
}

# access_log /dev/stdout;

server {
    listen 8000;
    listen [::]:8000;
    server_name _;

    root /takahe/static;
    index index.html;

    ignore_invalid_headers on;
    proxy_connect_timeout 900;

    client_max_body_size 100M;
    client_body_buffer_size 128k;
    charset utf-8;

    proxy_set_header Host $http_host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_http_version 1.1;

    # The user header is available for logging, but not returned to the client
    proxy_hide_header X-Takahe-User;
    proxy_hide_header X-Takahe-Identity;

    # Serves static files from the collected dir
    location /static/ {
        # Files in static have cache-busting hashes in the name, thus can be cached forever
        add_header Cache-Control "public, max-age=604800, immutable";

        alias /takahe/static-collected/;
        try_files $uri /static//static-real$uri;
    }

    # Static fallback for dev mode
    location /static-real/ {
        internal;
        proxy_pass http://takahe/;
    }

    # Proxies media and remote media with caching
    location ~* ^/(media|proxy) {
        # Cache media and proxied resources
        proxy_cache takahe;
        proxy_cache_key $host$uri;
        proxy_cache_valid 200 304 4h;
        proxy_cache_valid 301 307 4h;
        proxy_cache_valid 500 502 503 504 0s;
        proxy_cache_valid any 1h;
        add_header X-Cache $upstream_cache_status;

        # Signal to Takahē that we support full URI accel proxying
        proxy_set_header X-Takahe-Accel true;

        proxy_pass http://takahe;
    }

    # Internal target for X-Accel redirects that stashes the URI in a var
    location /__takahe_accel__/ {
        internal;
        set $takahe_realuri $upstream_http_x_takahe_realuri;
        rewrite ^/(.+) /__takahe_accel__/real/;
    }

    # Real internal-only target for X-Accel redirects
    location /__takahe_accel__/real/ {
        # Only allow internal redirects
        internal;

        # Reconstruct the remote URL
        resolver 9.9.9.9 149.112.112.112 ipv6=off;

        # Unset Authorization and Cookie for security reasons.
        proxy_set_header Authorization '';
        proxy_set_header Cookie '';

        # Stops the local disk from being written to (just forwards data through)
        proxy_max_temp_file_size 0;

        # Proxy the remote file through to the client
        proxy_pass $takahe_realuri;
        proxy_ssl_server_name on;
        add_header X-Takahe-Accel "HIT";

        # Cache these responses too
        proxy_cache takahe;
        # Cache after a single request
        proxy_cache_min_uses 1;
        proxy_cache_key $takahe_realuri;
        proxy_cache_valid 200 304 720h;
        proxy_cache_valid 301 307 12h;
        proxy_cache_valid 500 502 503 504 0s;
        proxy_cache_valid any 72h;
        add_header X-Cache $upstream_cache_status;
    }

    # Default config for all other pages
    location / {
        proxy_redirect off;
        proxy_buffering off;
        proxy_pass http://takahe;
    }
}
