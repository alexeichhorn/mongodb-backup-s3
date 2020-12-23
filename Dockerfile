FROM mongo

# Install Python and Cron
RUN apt-get update && apt-get -y install awscli cron

# install plugin for custom s3
RUN apt-get -y install python3-pip && pip3 install awscli-plugin-endpoint

ENV CRON_TIME="0 3 * * *" \
  TZ=US/Eastern \
  CRON_TZ=US/Eastern

ADD run.sh /run.sh
CMD /run.sh
