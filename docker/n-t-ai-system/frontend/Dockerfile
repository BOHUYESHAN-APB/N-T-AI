# Stage 1: Build Flutter Web
# Using master channel to support newer Dart SDK versions (e.g. 3.8.x)
FROM ghcr.io/cirruslabs/flutter:master AS build

WORKDIR /app

# Copy flutter files
COPY flutter_application/ .

# Get dependencies
RUN flutter pub get

# Build for web
RUN flutter build web --release --no-tree-shake-icons

# Stage 2: Serve with Nginx
FROM nginx:alpine

# Copy build artifacts
COPY --from=build /app/build/web /usr/share/nginx/html

# Copy custom Nginx config
COPY docker/n-t-ai-system/frontend/nginx.conf /etc/nginx/conf.d/default.conf


# Expose port
EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
