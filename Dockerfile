# syntax=docker/dockerfile:1

# ============================================================
# ChinaTextbookStudyFree 小学全科 AI 学习平台 — Docker 镜像
# 项目为 Next.js 纯静态站点（output: export），最终由 Nginx 托管。
# 构建时从 GitHub Release 下载资源（音频/故事配图/课本页/数据源），
# 国内网络可用 GH_MIRROR 加速（默认 gh-proxy.com，可改为直连）。
# ============================================================

# ---------- Stage 1: 下载并解压 Release 资源 ----------
FROM alpine:3.20 AS assets

# Release 标签（资源包版本）
ARG ASSETS_TAG=v1.1.0-assets
# 国内加速前缀；设为空字符串 "" 则直连 GitHub
ARG GH_MIRROR=https://gh-proxy.com
ARG BASE_URL=https://github.com/wuwangzhang1216/ChinaTextbookStudyFree/releases/download

RUN apk add --no-cache curl tar python3

WORKDIR /dl

RUN if [ -n "$GH_MIRROR" ]; then BASE_URL="$GH_MIRROR/$BASE_URL"; fi \
 && echo "==> 资源下载基址: $BASE_URL/$ASSETS_TAG" \
 && curl -fSL --retry 3 --retry-delay 5 -o audio.tar.gz         "$BASE_URL/$ASSETS_TAG/audio.tar.gz" \
 && curl -fSL --retry 3 --retry-delay 5 -o story-images.zip     "$BASE_URL/$ASSETS_TAG/story-images.zip" \
 && curl -fSL --retry 3 --retry-delay 5 -o textbook-pages.zip   "$BASE_URL/$ASSETS_TAG/textbook-pages.zip" \
 && curl -fSL --retry 3 --retry-delay 5 -o data-source.zip      "$BASE_URL/$ASSETS_TAG/data-source.zip" \
 && echo "==> 全部资源下载完成"

RUN mkdir -p /dl/public \
 && tar xzf audio.tar.gz -C /dl/public \
 && echo "==> 音频解压完成"

# Release 内 zip 为 Windows 反斜杠路径，需用 python 修正为正斜杠再解压
RUN python3 - <<'PY'
import os, zipfile
jobs = [
    ("/dl/story-images.zip",   "/dl/public/story-images"),
    ("/dl/textbook-pages.zip", "/dl/public/textbook-pages"),
    ("/dl/data-source.zip",    "/dl/data-source"),
]
for src, dst in jobs:
    os.makedirs(dst, exist_ok=True)
    with zipfile.ZipFile(src) as z:
        for name in z.namelist():
            fixed = name.replace("\\", "/")
            target = os.path.join(dst, fixed)
            if fixed.endswith("/"):
                os.makedirs(target, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with z.open(name) as sf, open(target, "wb") as df:
                df.write(sf.read())
print("==> 资源包解压完成")
PY

# ---------- Stage 2: 安装依赖并构建静态站点 ----------
FROM node:22-alpine AS builder

WORKDIR /app

# 复制源码（node_modules/.next/out/public 资源由 .dockerignore 排除）
COPY . .

# 覆盖为 assets 阶段下载的完整资源
COPY --from=assets /dl/public/audio           ./apps/web/public/audio
COPY --from=assets /dl/public/story-images     ./apps/web/public/story-images
COPY --from=assets /dl/public/textbook-pages   ./apps/web/public/textbook-pages
COPY --from=assets /dl/data-source             ./data

# 安装依赖（workspaces）并构建（build:data + next build -> apps/web/out/）
RUN npm ci --no-audit --no-fund \
 && npm run build

# ---------- Stage 3: Nginx 运行时 ----------
FROM nginx:1.27-alpine AS runtime

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/apps/web/out /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1
