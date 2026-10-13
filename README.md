Name
====

* ngx_http_upstream_dynamic_module

Description
===========

* This module provides the functionality to resolve domain names into IP addresses in an upstream at run-time.
* It comes from Taobao Tengine @ http://tengine.taobao.org

Compilation
===========

The patch `http-upstream-dynamic.patch` applies to nginx 1.10 through the latest
releases (tested with 1.18, 1.24, 1.26, 1.28, 1.30 and 1.31).

```
cd /path/to/nginx-source
patch -p0 < /path/to/nginx-http-upstream-dynamic-module/http-upstream-dynamic.patch

./configure --add-module=/path/to/nginx-http-upstream-dynamic-module
```

`http-upstream-dynamic.patch-1.14.0+` is kept as an alias of the same patch.

Examples
========

    resolver 8.8.8.8 valid=30s;

    upstream backend {
        dynamic_resolve fallback=stale fail_timeout=30s;

        server a.com;
        server b.com;
    }

    server {
        ...

        proxy_pass http://backend;
    }

Directives
==========

dynamic_resolve
---------------

**Syntax**: *dynamic_resolve [fallback=stale|next|shutdown] [fail_timeout=time]*

**Default**: *-*

**Context**: *upstream*

Enable dynamic DNS resolving functionality in an upstream.

Server names are resolved with the `resolver` configured in http, server or
location context (with nginx 1.27.3+, a `resolver` inside the upstream block
takes precedence). Every request resolves the name of the server chosen by the
load balancer, the result is cached according to the `valid` parameter of
`resolver` or the DNS TTL. Only the first address returned is used, so a server
name is a single peer in the upstream.

It works with all round robin based balancers: the default round robin, `hash`,
`ip_hash`, `least_conn` and `random`, as well as `keepalive`. Servers using the
`resolve` parameter of nginx 1.27.3+ are left to nginx itself.

The 'fallback' parameter specifies what action to take if a domain name can not be resolved into an IP address:

* stale, use the original IP addresses resolved when tengine starts.
* next, go to next availiable server in the upstream.
* shutdown, finalize current request.

The 'fail_timeout' parameter specifies how long time tengine considers the DNS server as unavailiable if a DNS query fails for a server in the upstream. In this period of time, all requests comming will follow what 'fallback' specifies.

Notes
=====

* It is a tengine module from
 https://github.com/alibaba/tengine/tree/master/modules/ngx_http_upstream_dynamic_module
 and made to work with nginx
* Since 1.27.3 nginx can re-resolve upstream servers natively with
 `server ... resolve;` (requires a `zone`), which may be an alternative to this module.
* It follows original tengine license.
