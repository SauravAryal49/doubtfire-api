# Config is baked into the image (not bind-mounted) so compose works when it
# is driven from inside the Jenkins container.
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/nginx.conf
