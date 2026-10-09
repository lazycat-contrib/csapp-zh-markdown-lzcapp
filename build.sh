#!/usr/bin/env bash
# csapp-zh-markdown 静态站构建：克隆上游源码（版本 tag）→ Quarto 渲染 → site/
# 由 LazyCat GitHub Action 的 buildscript 在每次构建时执行
set -euo pipefail

VERSION="${LAZYCAT_VERSION:-${VERSION:-}}"
echo "==> building csapp-zh-markdown version: ${VERSION:-<default branch>}"

rm -rf .upstream site
CLONE_OK=0
if [ -n "$VERSION" ]; then
  # 尝试多种 tag 形式：vX.Y.Z / vX.Y / X.Y.Z / X.Y / X.Y.0
  BASE="${VERSION%%.0}"
  for TAG in "v${VERSION}" "v${BASE}" "${VERSION}" "${BASE}"; do
    if [ -n "${TAG}" ] && git clone --depth 1 --branch "$TAG" https://github.com/SunnyMaria/csapp-zh-markdown.git .upstream 2>/dev/null; then
      echo "==> cloned tag $TAG"
      CLONE_OK=1
      break
    fi
  done
fi
if [ "$CLONE_OK" != "1" ]; then
  echo "==> tag not found, falling back to default branch"
  git clone --depth 1 https://github.com/SunnyMaria/csapp-zh-markdown.git .upstream
fi

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
if [ -f .upstream/website/requirements.txt ]; then
  python3 -m pip install --user --upgrade pip >/dev/null 2>&1 || true
  python3 -m pip install --user -r .upstream/website/requirements.txt >/dev/null
  export PATH="$HOME/.local/bin:$PATH"
fi

# 生成页面 + 渲染
cd .upstream
python3 website/scripts/build.py
echo "==> rendering with Quarto"
echo "pwd=$(pwd)"
echo "quarto=$(command -v quarto)"
cd website/build
quarto render . > /tmp/quarto-render.log 2>&1
RENDER_RC=$?
cd ../..
echo "---- quarto render log (first 40 lines) ----"
head -40 /tmp/quarto-render.log || true
echo "---- quarto render log (last 15 lines) ----"
tail -15 /tmp/quarto-render.log || true
echo "==> quarto render exit code: ${RENDER_RC}"

# 渲染完整性校验：必须产出 index.html 与全部页面（499 页），否则 fail（避免静默产出空站）
SITE_DIR="website/build/_site"
if [ "${RENDER_RC}" != "0" ] || [ ! -f "${SITE_DIR}/index.html" ]; then
  echo "ERROR: Quarto render failed or produced no index.html" >&2
  echo "---- _site listing ----" >&2
  ls -la "${SITE_DIR}" 2>&1 | head -30 >&2
  echo "---- build dir ----" >&2
  ls "${SITE_DIR}/../" 2>&1 | head -30 >&2
  exit 1
fi
PAGE_COUNT="$(find "${SITE_DIR}" -name '*.html' | wc -l)"
echo "==> render check: ${PAGE_COUNT} html pages"
if [ "${PAGE_COUNT}" -lt 100 ]; then
  echo "ERROR: too few rendered pages (${PAGE_COUNT} < 100)" >&2
  exit 1
fi
cd ..
cp -r .upstream/website/build/_site site
echo "==> site built: $(du -sh site | cut -f1), pages: ${PAGE_COUNT}"
