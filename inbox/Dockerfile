FROM golang:1.26-trixie

RUN apt-get update && apt-get install -y --no-install-recommends cron && rm -rf /var/lib/apt/lists/*

RUN addgroup --system service
RUN adduser --system --ingroup service --uid 1000 service

RUN mkdir /maildir/
RUN chown service:service /maildir/

COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

COPY cleanup.sh /
RUN chmod 0755 /cleanup.sh
COPY cron.d/inbox-cleanup /etc/cron.d/inbox-cleanup
RUN chmod 0644 /etc/cron.d/inbox-cleanup

COPY src /service/

COPY gov_verify /service/
COPY gov_public.pem /service/

WORKDIR /service/inbox

RUN go build -o /service/inboxd /service/inbox/cmd/inboxd

WORKDIR /service/
EXPOSE 1234
EXPOSE 4321

ENTRYPOINT ["/entrypoint.sh"]
