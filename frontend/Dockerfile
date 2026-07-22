# The frontend is plain static HTML/JS with no build step, so nginx just
# needs to serve the file — no Node.js toolchain required.
FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
