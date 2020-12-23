#!/bin/bash

MONGODB_HOST=${MONGODB_PORT_27017_TCP_ADDR:-${MONGODB_HOST}}
MONGODB_HOST=${MONGODB_PORT_1_27017_TCP_ADDR:-${MONGODB_HOST}}
MONGODB_PORT=${MONGODB_PORT_27017_TCP_PORT:-${MONGODB_PORT}}
MONGODB_PORT=${MONGODB_PORT_1_27017_TCP_PORT:-${MONGODB_PORT}}
MONGODB_USER=${MONGODB_USER:-${MONGODB_ENV_MONGODB_USER}}
MONGODB_PASS=${MONGODB_PASS:-${MONGODB_ENV_MONGODB_PASS}}

S3PATH="s3://$BUCKET/$BACKUP_FOLDER"

[[ ( -n "${BUCKET_REGION}" ) ]] && REGION_STR=" --region ${BUCKET_REGION}"

[[ ( -z "${MONGODB_USER}" ) && ( -n "${MONGODB_PASS}" ) ]] && MONGODB_USER='admin'

[[ ( -n "${MONGODB_USER}" ) ]] && USER_STR=" --username ${MONGODB_USER}"
[[ ( -n "${MONGODB_PASS}" ) ]] && PASS_STR=" --password ${MONGODB_PASS}"
[[ ( -n "${MONGODB_DB}" ) ]] && DB_STR=" --db ${MONGODB_DB}"

# Export AWS Credentials into env file for cron job
printenv | sed 's/^\([a-zA-Z0-9_]*\)=\(.*\)$/export \1="\2"/g' | grep -E "^export AWS" > /root/project_env.sh

aws configure set default.s3.signature_version s3v4
aws configure set plugins.endpoint awscli_plugin_endpoint
aws configure set default.region ${BUCKET_REGION}
aws configure set default.s3.max_concurrent_requests 100
aws configure set default.s3.max_queue_size 1000
aws configure set default.s3.multipart_threshold 50GB
aws configure set default.s3.multipart_chunksize 5GB
aws configure set default.s3.endpoint_url ${S3_ENDPOINT}
aws configure set default.s3api.endpoint_url ${S3_ENDPOINT}
aws configure set default.aws_access_key_id ${AWS_ACCESS_KEY}
aws configure set default.aws_secret_access_key ${AWS_SECRET_ACCESS_KEY}

echo "=> Creating backup script"
rm -f /backup.sh
cat <<EOF >> /backup.sh
#!/bin/bash
TIMESTAMP=\`/bin/date +"%Y-%m-%dT_%H-%M-%S"\`
BACKUP_NAME=\${TIMESTAMP}.dump.gz
S3BACKUP=${S3PATH}\${BACKUP_NAME}
S3LATEST=${S3PATH}latest.dump.gz

echo "=> Backup started"
if mongodump --host ${MONGODB_HOST} --port ${MONGODB_PORT} ${USER_STR}${PASS_STR}${DB_STR} --archive=\${BACKUP_NAME} --gzip ${EXTRA_OPTS} && aws s3 cp \${BACKUP_NAME} \${S3BACKUP} ${REGION_STR} && aws s3 cp \${S3BACKUP} \${S3LATEST} ${REGION_STR} && rm \${BACKUP_NAME} ;then
    echo "   > Backup succeeded"
else
    echo "   > Backup failed"
fi
echo "=> Done"
EOF
chmod +x /backup.sh
echo "=> Backup script created"

echo "=> Creating restore script"
rm -f /restore.sh
cat <<EOF >> /restore.sh
#!/bin/bash
if [[( -n "\${1}" )]];then
    RESTORE_ME=\${1}.dump.gz
else
    RESTORE_ME=latest.dump.gz
fi
S3RESTORE=${S3PATH}\${RESTORE_ME}
aws configure set default.s3.signature_version s3v4
echo "=> Restore database from \${RESTORE_ME}"
if aws s3 cp \${S3RESTORE} \${RESTORE_ME} ${REGION_STR} && mongorestore --host ${MONGODB_HOST} --port ${MONGODB_PORT} ${USER_STR}${PASS_STR}${DB_STR} --drop --archive=\${RESTORE_ME} --gzip && rm \${RESTORE_ME}; then
    echo "   Restore succeeded"
else
    echo "   Restore failed"
fi
echo "=> Done"
EOF
chmod +x /restore.sh
echo "=> Restore script created"

echo "=> Creating list script"
rm -f /listbackups.sh
cat <<EOF >> /listbackups.sh
#!/bin/bash
aws s3 ls ${S3PATH} \${REGION_STR}
EOF
chmod +x /listbackups.sh
echo "=> List script created"

ln -s /restore.sh /usr/bin/restore
ln -s /backup.sh /usr/bin/backup
ln -s /listbackups.sh /usr/bin/listbackups

touch /mongo_backup.log

if [ -n "${INIT_BACKUP}" ]; then
    echo "=> Create a backup on the startup"
    /backup.sh
fi

if [ -n "${INIT_RESTORE}" ]; then
    echo "=> Restore store from lastest backup on startup"
    /restore.sh
fi

if [ -z "${DISABLE_CRON}" ]; then
    echo "${CRON_TIME} . /root/project_env.sh; /backup.sh >> /mongo_backup.log 2>&1" > /crontab.conf
    crontab  /crontab.conf
    echo "=> Running cron job"
    cron && tail -f /mongo_backup.log
fi
