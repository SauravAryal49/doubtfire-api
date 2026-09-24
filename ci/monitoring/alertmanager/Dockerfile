FROM prom/alertmanager:v0.27.0
COPY alertmanager.yml.tmpl /etc/alertmanager/alertmanager.yml.tmpl
# Inject the webhook secret at start-up (Alertmanager has no env-var support)
ENTRYPOINT ["/bin/sh", "-c", "sed \"s|__DISCORD_WEBHOOK_URL__|${DISCORD_WEBHOOK_URL}|\" /etc/alertmanager/alertmanager.yml.tmpl > /tmp/alertmanager.yml && exec /bin/alertmanager --config.file=/tmp/alertmanager.yml --storage.path=/alertmanager"]
