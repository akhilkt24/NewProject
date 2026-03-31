# Stage 1 — Build
FROM node:20-alpine AS builder

WORKDIR /app

# Install yarn globally
RUN npm install -g yarn

# Install dependencies using yarn (more stable than npm in Docker)
COPY package*.json ./
RUN yarn install --frozen-lockfile

# Copy source and build
COPY . .
RUN yarn build

# Stage 2 — Serve with Nginx
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
