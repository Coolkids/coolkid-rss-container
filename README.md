# Coolkid RSS Container

用于构建和运行 Coolkid RSS 的单容器部署项目。

镜像在构建阶段会分别拉取并编译：

- 后端：[Coolkids/coolkid-rss-webflux](https://github.com/Coolkids/coolkid-rss-webflux)
- 前端：[Coolkids/coolkid-rss-web](https://github.com/Coolkids/coolkid-rss-web)
- 影视标题解析依赖：[Coolkids/anitopy4j](https://github.com/Coolkids/anitopy4j)

`anitopy4j` 通过 GitHub 仓库远程拉取，并在 Docker 构建后端之前安装到构建容器的 Maven 本地仓库中。镜像构建不依赖宿主机上的本地项目目录。

运行时由同一个容器提供前端页面和后端 API：Nginx 监听 `80` 端口，Supervisor 负责同时启动 Nginx 与 Spring Boot 后端。

## 架构

```text
客户端 :80
   |
   +-- /coolkid-rss/api/*  --> Nginx --> 后端 :8081
   |
   +-- 其他路径             --> Nginx --> 前端静态文件
                                      |
                                      +-- Vue Router fallback: /index.html
```

## 快速开始

### 使用预构建镜像

```bash
docker pull ghcr.io/coolkids/coolkid-rss:latest
docker run -d \
  --name coolkid-rss \
  --restart unless-stopped \
  -p 8080:80 \
  -e TZ=Asia/Shanghai \
  ghcr.io/coolkids/coolkid-rss:latest
```

启动后访问：<http://localhost:8080>

### 本地构建

本项目使用 Dockerfile 的 BuildKit cache mount，建议使用 Docker 23+ 或
`docker buildx` 构建：

```bash
cd /home/coolkid/code/coolkid-rss-container
docker build -t coolkid-rss:local .
docker run -d \
  --name coolkid-rss \
  --restart unless-stopped \
  -p 8080:80 \
  coolkid-rss:local
```

## 构建参数

`Dockerfile` 支持通过 `--build-arg` 指定后端、前端、`anitopy4j` 仓库及其分支或标签：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `BACKEND_REPO` | `https://github.com/Coolkids/coolkid-rss-webflux.git` | 后端 Git 仓库 |
| `BACKEND_REF` | `main` | 后端分支或标签 |
| `FRONTEND_REPO` | `https://github.com/Coolkids/coolkid-rss-web.git` | 前端 Git 仓库 |
| `FRONTEND_REF` | `main` | 前端分支或标签 |
| `ANITOPY_REPO` | `https://github.com/Coolkids/anitopy4j.git` | `anitopy4j` Git 仓库 |
| `ANITOPY_REF` | `main` | `anitopy4j` 分支或标签 |

例如，构建指定版本：

```bash
docker build \
  --build-arg BACKEND_REF=v1.0.0 \
  --build-arg FRONTEND_REF=v1.0.0 \
  --build-arg ANITOPY_REF=main \
  -t coolkid-rss:v1.0.0 .
```

构建阶段使用 Maven 和 Node.js，顺序如下：

1. 从 `ANITOPY_REPO` 拉取 `ANITOPY_REF`。
2. 执行 `mvn -f /build/anitopy4j/pom.xml install -DskipTests`，将依赖安装到构建容器的 Maven 仓库。
3. 从 `BACKEND_REPO` 拉取后端并执行 `mvn clean package -DskipTests`。
4. 从 `FRONTEND_REPO` 拉取前端并执行 `npm install && npm run build`。

后端的 Maven 依赖坐标为 `io.github.coolkid:anitopy4j:1.0.0-SNAPSHOT`。如果只在宿主机直接构建后端而不使用本 Dockerfile，需要先安装远程依赖：

```bash
git clone --depth 1 https://github.com/Coolkids/anitopy4j.git
mvn -f anitopy4j/pom.xml install -DskipTests
```

## 运行配置

容器默认设置：

- 对外监听 `80` 端口，宿主机可按需映射到其他端口。
- 时区为 `Asia/Shanghai`，可通过 `TZ` 覆盖。
- Java 启动参数默认为空，可通过 `JAVA_OPTS` 传入，例如：

  ```bash
  -e JAVA_OPTS="-Xms256m -Xmx512m"
  ```

- 后端在容器内部监听 `8081`，Nginx 将 `/coolkid-rss/api/` 请求转发到该地址。
- 容器内置健康检查，会请求 `http://127.0.0.1/`。

查看容器日志：

```bash
docker logs -f coolkid-rss
```

## 后端配置

后端的默认配置位于 `coolkid-rss-webflux` 的
`src/main/resources/application.properties`，容器部署时通过环境变量覆盖：

| 环境变量 | 对应配置 | 默认值 | 说明 |
| --- | --- | --- | --- |
| `CRW_MONGODB_URL` | `spring.data.mongodb.uri` | 无 | MongoDB 连接 URI，必填 |
| `CRW_REDIS_HOST` | `spring.data.redis.host` | 无 | Redis 主机，必填 |
| `CRW_REDIS_PORT` | `spring.data.redis.port` | `6379` | Redis 端口 |
| `CRW_REDIS_PW` | `spring.data.redis.password` | 无 | Redis 密码；无密码时显式设置为空字符串 |
| `CRW_REDIS_DB` | `spring.data.redis.database` | `1` | Redis 数据库编号 |
| `CRW_SERVER_LOG_LEVEL` | `logging.level.root` | `info` | 根日志级别 |
| `CRW_SERVER_LOG_NAME` | `logging.file.name` | `coolkidrss.log` | 日志文件名 |
| `CRW_SNID_DB` | `coolkidrss.databaseId` | `1` | Snowflake 数据库标识，范围 `0–31` |
| `CRW_SNID_ND` | `coolkidrss.nodeId` | `1` | Snowflake 节点标识，范围 `0–31` |
| `CRW_SETTING_CLEAN_DATA` | `coolkidrss.clean.data` | `false` | 是否清理历史数据 |
| `CRW_SETTING_CLEAN_DATA_MONTH` | `coolkidrss.keep.data.month` | `12` | 保留最近多少个月的数据 |
| `CRW_RSS_CODE_PATCH_MAX_BYTES` | `coolkidrss.rss.code.patch.max-bytes` | `524288` | 代码类型 RSS 单条提交 patch 最大保存字节数；超出后截断，避免大 patch 占用过多内存和存储 |

后端默认监听 `8081` 端口，并挂载在 `/coolkid-rss` 路径下；容器内的 Nginx 会将 `/coolkid-rss/api/` 请求转发到后端。

## Docker Compose 示例

下面的示例会启动 Coolkid RSS、MongoDB 和 Redis，并将数据保存到 Docker 命名卷。示例使用无认证的 MongoDB 和 Redis，仅适合个人或内网部署；生产环境建议启用认证并替换连接配置。

```yaml
services:
  coolkid-rss:
    image: ghcr.io/coolkids/coolkid-rss:latest
    container_name: coolkid-rss
    restart: unless-stopped
    depends_on:
      mongodb:
        condition: service_healthy
      redis:
        condition: service_healthy
    ports:
      - "8080:80"
    environment:
      TZ: Asia/Shanghai

      # 后端：MongoDB
      CRW_MONGODB_URL: mongodb://mongodb:27017/coolkid_rss

      # 后端：Redis
      CRW_REDIS_HOST: redis
      CRW_REDIS_PORT: "6379"
      CRW_REDIS_PW: ""
      CRW_REDIS_DB: "1"

      # 后端运行参数
      CRW_SERVER_LOG_LEVEL: info
      CRW_SNID_DB: "1"
      CRW_SNID_ND: "1"
      CRW_SETTING_CLEAN_DATA: "false"
      CRW_SETTING_CLEAN_DATA_MONTH: "12"
      # 代码类型 RSS 的 patch 最大保存/预览大小（字节）
      CRW_RSS_CODE_PATCH_MAX_BYTES: "524288"

    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1/ || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s

  mongodb:
    image: mongo:8
    container_name: coolkid-rss-mongodb
    restart: unless-stopped
    volumes:
      - mongodb-data:/data/db
    healthcheck:
      test: ["CMD-SHELL", "mongosh --quiet --eval 'db.adminCommand({ ping: 1 }).ok' | grep 1"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: coolkid-rss-redis
    restart: unless-stopped
    volumes:
      - redis-data:/data
    command: redis-server --appendonly yes
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  mongodb-data:
  redis-data:
```

将内容保存为 `docker-compose.yml` 后执行：

```bash
docker compose up -d
docker compose ps
docker compose logs -f coolkid-rss
```

启动后访问 <http://localhost:8080>。停止服务但保留数据：

```bash
docker compose down
```

如果使用带认证的 MongoDB 或 Redis，请同步修改 `CRW_MONGODB_URL`、`CRW_REDIS_PW`，并按实际认证方式配置对应数据库服务。

> 注意：后端的 `RssIdUtil` 会直接读取打包进 JAR 的 `application.properties`。因此 `CRW_SNID_DB` 和 `CRW_SNID_ND` 在当前后端实现中不应被视为可靠的动态覆盖方式；单实例建议使用默认值，多实例部署前应先验证节点 ID 是否实际生效，并为各实例配置不重复的组合。

## CI/CD

`.github/workflows/docker.yml` 会在以下情况触发构建并推送镜像到 GitHub Container Registry：

- 推送到 `main` 分支
- 推送匹配 `v*` 的标签
- 手动触发 workflow

默认镜像地址为 `ghcr.io/coolkids/coolkid-rss`。手动触发时可以分别指定 `backend_ref`、`frontend_ref` 和 `anitopy_ref`，用于构建不同的后端、前端和 `anitopy4j` 分支或标签。

工作流当前构建 `linux/amd64` 镜像，并使用 GitHub Actions cache 加速后续构建。

## 相关文件

| 文件 | 用途 |
| --- | --- |
| `Dockerfile` | 多阶段构建后端、前端和最终运行镜像 |
| `nginx.conf` | 静态文件服务、API 反向代理及压缩配置 |
| `supervisord.conf` | 管理后端和 Nginx 进程 |
| `.github/workflows/docker.yml` | 自动构建并推送 Docker 镜像 |

## 注意事项

- 构建时需要能够访问 GitHub、Maven 仓库和 npm Registry。
- `anitopy4j` 是构建时从 `https://github.com/Coolkids/anitopy4j.git` 拉取的远程依赖；如需固定版本，使用 `ANITOPY_REF` 指定分支或标签。
- 后端和前端仓库的指定分支或标签必须存在，并且产物路径需要分别包含 `target/coolkid-rss.jar` 和 `dist/spa/`。
- 当前镜像只声明并构建 `linux/amd64` 平台；在 ARM 设备上运行时建议使用兼容模拟，或扩展 CI 构建平台配置。
