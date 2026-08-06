# The frontend is plain static HTML/JS with no build step, so nginx just
# needs to serve the file — no Node.js toolchain required.
FROM nginx:alpine                            # nginx on Alpine Linux: about 8 MB total; Alpine is a minimal distro, appropriate when all you're doing is serving a static file

COPY index.html /usr/share/nginx/html/index.html  # nginx's default root is /usr/share/nginx/html; dropping the file here is all that's needed — nginx serves it at GET /

EXPOSE 80                                    # nginx's default port; Compose maps this to 8080 on the host (see ports: "8080:80" in docker-compose.yml)
