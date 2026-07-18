# --- build stage ---
FROM node:22-alpine@sha256:16e22a550f3863206a3f701448c45f7912c6896a62de43add43bb9c86130c3e2 AS build
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

COPY tsconfig.json vite.config.ts index.html ./
COPY src ./src
RUN npm run build

# --- runtime stage ---
FROM nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0
COPY nginx-upgrade-map.conf /etc/nginx/conf.d/00-upgrade-map.conf
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 8080
