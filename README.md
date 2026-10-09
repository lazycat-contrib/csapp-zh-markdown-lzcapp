# csapp-zh-markdown-lzcapp

[CSAPP 中文 Markdown 学习资料](https://github.com/SunnyMaria/csapp-zh-markdown)的懒猫微服打包。

《深入理解计算机系统》（CSAPP，第三版）中文学习资料：按章节拆分的正文、习题与原书答案，以及八个实验的中文说明——以在线阅读站形式呈现（章节导航、全文搜索、深色模式）。

## 交付方式（静态站，无容器镜像）

沿用内容型应用的「静态嵌入」模式：

1. `build.sh`（`lzc-build.yml` 的 buildscript）在构建时克隆上游源码（对应版本 tag）→
   安装 Quarto → `python3 website/scripts/build.py` 生成页面 → `quarto render` 渲染 → 产出 `site/`
2. `contentdir: ./site` 把静态站打包进 LPK
3. `lzc-manifest.yml` 用平台内置的文件服务（`backend: file:///lzcapp/pkg/content/`）直接提供网页，
   **不需要任何容器镜像**

## 更新流程

- 每日定时任务比对上游 release tag（`v1.2` → `1.2.0` 归一为 SemVer），有新版本时自动 bump
  `package.yml` 并触发发布；也可以手动触发 workflow 从上游默认分支构建。

## 维护注意（勿踩的坑）

- **克隆目录不能用隐藏名**：`build.sh` 把上游克隆到 `upstream/`，**不要改成 `.upstream/`
  之类的点开头目录**。Quarto 的文件扫描器不会进入隐藏目录，会导致 `website/build` 下
  499 个 qmd 全部不可见（项目输入为 0），`quarto render` 以退出码 0 静默产出只有
  `sitemap.xml`/`robots.txt` 的空站。
- `build.sh` 内置两道自检：Quarto 发现的输入数（<100 即失败）与渲染页数（<100 即失败），
  空站会在 CI 直接报错而不是发布坏包。

## 版权

内容来自 [SunnyMaria/csapp-zh-markdown](https://github.com/SunnyMaria/csapp-zh-markdown)，
遵循其许可证（CC BY-NC-SA 4.0）；本仓库仅为打包，不修改上游内容。
