# Architecture

The implementation borrows HestiaCP's useful domain-oriented choices: PHP version belongs to the domain, each domain has an FPM pool, and generated configuration is version-specific. It does not copy Hestia's global PHP editor behavior, which can merge multiple `php.ini` files.

MyVesta-specific integration uses `VESTA_CMD`, `/usr/local/vesta/bin`, `v-get-php-version-of-domain`, native `render_page()` templates, existing CSS classes, session messages and the existing token convention.

Persistent domain values live outside generated pools. The rebuild hook reapplies them after MyVesta regenerates web-domain configuration.

The resource advisor uses a conservative budget:

```text
total RAM - reserved system/services memory = PHP-FPM budget
pool budget / estimated worker RSS = suggested pm.max_children
```

The initial worker estimate is deliberately conservative. Future versions can replace it with observed RSS P95/P99 metrics.
