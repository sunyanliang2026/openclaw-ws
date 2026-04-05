# Deployment

## Goal

Expose only one public entry point for the app.

- public traffic goes to `Caddy`
- `Caddy` reverse proxies to the Next frontend
- the Next frontend proxies `/api/detect/*` to the Flask backend over the internal Docker network
- the Flask backend is **not** exposed publicly

This removes the earlier need for a separate public backend URL.

## Files

- `docker-compose.yml`
- `Caddyfile`
- `backend/Dockerfile`
- `frontend/Dockerfile`

## Prerequisites

- Docker
- Docker Compose plugin
- a domain name pointing to the server
- ports `80` and `443` open on the server/security group

## Recommended DNS

Point your domain A record to the server public IP.

Example:

- `detect.example.com -> your_server_public_ip`

## Environment

Create a root `.env` file next to `docker-compose.yml`.

Example:

```env
APP_DOMAIN=detect.example.com
NEXT_PUBLIC_APP_URL=https://detect.example.com
NEXT_PUBLIC_APP_NAME=AI Fake Detect System
NEXT_PUBLIC_APP_DESCRIPTION=AI Fake Detect System
NEXT_PUBLIC_DEFAULT_LOCALE=en
NEXT_PUBLIC_LOCALE_DETECT_ENABLED=false
AUTH_SECRET=replace-this-with-a-real-secret
DATABASE_PROVIDER=sqlite
DATABASE_URL=file:data/local.db
DB_SCHEMA_FILE=./src/config/db/schema.sqlite.ts
DB_MIGRATIONS_OUT=./src/config/db/migrations_sqlite
DB_SINGLETON_ENABLED=true
DB_MAX_CONNECTIONS=1
```

Notes:

- `NEXT_PUBLIC_API_BASE_URL` does **not** need to be public in production here.
- `docker-compose.yml` sets it internally to `http://backend:5001`.
- only `Caddy` publishes ports externally.

## Start

From the repo root:

```bash
docker compose up -d --build
```

## Check

```bash
docker compose ps
docker compose logs -f caddy
docker compose logs -f frontend
docker compose logs -f backend
```

Open:

- `https://your-domain/`
- `https://your-domain/detect`

## Dev Tunnel Note

For temporary external testing in dev mode, you can still use a tunnel service.
If Next dev warns about cross-origin dev asset requests, set:

```env
NEXT_ALLOWED_DEV_ORIGINS=your-dev-tunnel.example
```

in `frontend/.env.development`, then restart `corepack pnpm dev`.

## Architecture Note

The browser now talks only to the frontend origin:

- browser -> `/api/detect/text`
- browser -> `/api/detect/image`

The frontend server forwards those requests to Flask internally.
That is the intended long-term deployment shape.
