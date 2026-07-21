FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY apps/admin_web/package.json apps/admin_web/package.json
COPY packages/shared-contracts/package.json packages/shared-contracts/package.json
COPY packages/design-tokens/package.json packages/design-tokens/package.json
RUN npm ci
COPY . .
ARG VITE_SUPABASE_URL
ARG VITE_SUPABASE_PUBLISHABLE_KEY
ARG VITE_ENABLE_DEV_MOCKS=false
ENV VITE_SUPABASE_URL=$VITE_SUPABASE_URL
ENV VITE_SUPABASE_PUBLISHABLE_KEY=$VITE_SUPABASE_PUBLISHABLE_KEY
ENV VITE_ENABLE_DEV_MOCKS=$VITE_ENABLE_DEV_MOCKS
RUN npm run build

FROM nginx:1.27-alpine
COPY deploy/web/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/apps/admin_web/dist /usr/share/nginx/html
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD wget -q -O - http://127.0.0.1:8080/healthz || exit 1
