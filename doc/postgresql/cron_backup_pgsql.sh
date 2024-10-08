#!/bin/bash
# cp -rf /www/wwwroot/imboy-api/doc/postgresql/cron_backup_pgsql.sh /data/docker/imboy_pg15 && chmod +x /data/docker/imboy_pg15

# docker exec -it imboy_pg15 /bin/sh
# crontab -e 新增下面一行
# 0 3 * * * /usr/bin/docker exec imboy_pg15 /bin/sh /var/lib/postgresql/data/cron_backup_pgsql.sh
# /usr/bin/docker exec imboy_pg15 pg_dump -h 127.0.0.1 -p 5432 -U imboy_user -d imboy_v1 -s -f /var/lib/postgresql/data/back_pgsql/imboy_v1_dev.sql

#
# 进入 pgsql的docker容器
# clear && docker container exec -it imboy_pg15 bash
# /var/lib/postgresql/data/ 等价于 宿主机的 /data/docker/imboy_pg15 目录
mkdir -p /var/lib/postgresql/data/back_pgsql && cd /var/lib/postgresql/data/back_pgsql
# 备份
pg_dump -h 127.0.0.1 --inserts -d imboy_v1 -U imboy_user -p 5432  -f imboy_v1.sql
tar -czf imboy_v1_$(date +%Y-%m-%d_%H-%M).tar.gz imboy_v1.sql && rm -rf imboy_v1.sql

# 保留 imboy_v1_*.tar.gz 最新10个文件
ls -t /var/lib/postgresql/data/back_pgsql | tail -n +11 | xargs -i rm -rf /var/lib/postgresql/data/back_pgsql/{}
