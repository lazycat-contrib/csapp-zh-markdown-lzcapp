#!/usr/bin/env bash
# csapp-zh-markdown 静态站构建：克隆上游源码（版本 tag）→ Quarto 渲染 → site/
# 由 LazyCat GitHub Action 的 buildscript 在每次构建时执行
set -euo pipefail

VERSION="${LAZYCAT_VERSION:-${VERSION:-}}"
echo "==> building csapp-zh-markdown version: ${VERSION:-<default branch>}"

# 注意：clone 目录必须使用「不以 . 开头」的名字。
# Quarto 的文件扫描器不会进入隐藏目录（.upstream/...），会导致 project 输入为 0、
# render 静默产出空站。历史上这里用过 .upstream 并因此踩坑，勿改回。
rm -rf upstream site
CLONE_OK=0
if [ -n "$VERSION" ]; then
  # 尝试多种 tag 形式：vX.Y.Z / vX.Y / X.Y.Z / X.Y / X.Y.0
  BASE="${VERSION%%.0}"
  for TAG in "v${VERSION}" "v${BASE}" "${VERSION}" "${BASE}"; do
    if [ -n "${TAG}" ] && git clone --depth 1 --branch "$TAG" https://github.com/SunnyMaria/csapp-zh-markdown.git upstream 2>/dev/null; then
      echo "==> cloned tag $TAG"
      CLONE_OK=1
      break
    fi
  done
fi
if [ "$CLONE_OK" != "1" ]; then
  echo "==> tag not found, falling back to default branch"
  git clone --depth 1 https://github.com/SunnyMaria/csapp-zh-markdown.git upstream
fi
# 删除 clone 的 .git：构建区不参与 git，避免任何 ignore 语义干扰 Quarto 的文件发现
rm -rf upstream/.git

# 安装 Quarto（静态 tarball，无需 root）
QUARTO_VERSION=1.9.38
if ! command -v quarto >/dev/null 2>&1; then
  echo "==> installing Quarto ${QUARTO_VERSION}"
  curl -sL -o /tmp/quarto.tar.gz "https://github.com/quarto-dev/quarto-cli/releases/download/v${QUARTO_VERSION}/quarto-${QUARTO_VERSION}-linux-amd64.tar.gz"
  mkdir -p "$HOME/quarto"
  tar -xzf /tmp/quarto.tar.gz -C "$HOME/quarto"
  export PATH="$HOME/quarto/quarto-${QUARTO_VERSION}/bin:$PATH"
fi
quarto --version

# Python 依赖：main 分支的 build.py 需要 Pillow（读取图片尺寸），
# v1.2 及更早的 build.py 不依赖第三方库（也没有 requirements.txt）。
if [ -f upstream/website/requirements.txt ]; then
  python3 -m pip install --user --upgrade pip >/dev/null 2>&1 || true
  python3 -m pip install --user -r upstream/website/requirements.txt >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
fi

# 生成页面 + 渲染
cd upstream
python3 website/scripts/build.py
echo "==> rendering with Quarto"
cd website/build

# 自检：先确认 Quarto 能发现项目输入（远低于预期即视为构建配置错误，快速失败）
INPUT_COUNT="$(quarto inspect . 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("files",{}).get("input",[])))' 2>/dev/null || echo 0)"
echo "==> quarto discovered inputs: ${INPUT_COUNT}"
if [ "${INPUT_COUNT}" -lt 100 ]; then
  echo "ERROR: Quarto found ${INPUT_COUNT} input files (expected 400+); aborting." >&2
  exit 1
fi

set +e
quarto render . 2>&1 | tee /tmp/quarto-render.log
RENDER_RC="${PIPESTATUS[0]}"
set -e
echo "==> quarto render exit code: ${RENDER_RC}"

# 渲染完整性校验：必须产出 index.html 与全部页面（约 499 页），否则 fail
cd ../../..
SITE_DIR="upstream/website/build/_site"
if [ "${RENDER_RC}" != "0" ] || [ ! -f "${SITE_DIR}/index.html" ]; then
  echo "ERROR: Quarto render failed or produced no index.html" >&2
  echo "---- _site listing ----" >&2
  ls -la "${SITE_DIR}" 2>&1 | head -30 >&2
  exit 1
fi
PAGE_COUNT="$(find "${SITE_DIR}" -name '*.html' | wc -l)"
echo "==> render check: ${PAGE_COUNT} html pages"
if [ "${PAGE_COUNT}" -lt 100 ]; then
  echo "ERROR: too few rendered pages (${PAGE_COUNT} < 100)" >&2
  exit 1
fi
cp -r "${SITE_DIR}" site
echo "==> site built: $(du -sh site | cut -f1), pages: ${PAGE_COUNT}"
