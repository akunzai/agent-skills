# Fixture Storefront

## Running locally

Bring the stack up with `docker compose up -d`, wait for the web
container, then open http://localhost:8080. The first run asks you to
paste a Stripe test key when prompted.

Health check: `curl -fsS http://localhost:8080/healthz`.
