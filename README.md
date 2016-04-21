Name
====

* ngx_http_upstream_dynamic_module

Description
===========

* This module provides the functionality to resolve domain names into IP addresses in an upstream at run-time.
* It comes from Taobao Tengine @ http://tengine.taobao.org

Compilation
===========

```
patch -p0 < /path/to/nginx-http-upstream-dynamic-module/http-upstream-dynamic.patch
./configure --add-module=/path/to/nginx-http-upstream-dynamic-module
```

Examples
========

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

The 'fallback' parameter specifies what action to take if a domain name can not be resolved into an IP address:

* stale, use the original IP addresses resolved when tengine starts.
* next, go to next availiable server in the upstream.
* shutdown, finalize current request.

The 'fail_timeout' parameter specifies how long time tengine considers the DNS server as unavailiable if a DNS query fails for a server in the upstream. In this period of time, all requests comming will follow what 'fallback' specifies.

Notes
=====

* It is a tengine module from
 https://github.com/alibaba/tengine/blob/master/src/http/modules/ngx_http_upstream_dynamic_module.c
 and made to work with nginx 1.9
* It follows original tengine license.
