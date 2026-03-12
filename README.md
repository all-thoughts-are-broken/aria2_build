# aria2 Minimal Static Packages

## 中文

这个仓库只负责打包，不提交上游源码。GitHub Actions 会在构建时拉取：

- `aria2`：用于 Linux / macOS
- `Mile.Aria2`：用于 Windows MSVC `/MT`

目标是产出面向 HTTP/HTTPS 下载场景的静态库分发包，结构统一为：

```text
include/
  aria2/
    aria2.h
lib/
  libaria2.a        # Linux / macOS
  aria2.lib         # Windows
  zlib.lib          # Windows 额外静态依赖
cmake/
  Aria2Config.cmake
  Aria2ConfigVersion.cmake
```

### 当前裁剪范围

构建会关闭这些可裁剪的非 HTTP 功能：

- BitTorrent
- Metalink
- WebSocket
- XML-RPC
- SFTP / libssh2
- SQLite Cookie DB
- Expat / libxml2 相关功能

补充说明：

- Windows 产物基于 `Mile.Aria2.Library`，Release 配置使用 `/MT`
- macOS 使用系统 `Apple TLS`
- Linux 使用系统 `OpenSSL + zlib`
- 上游没有单独的 FTP 编译开关，所以这个仓库的定位是“面向 HTTP/HTTPS 使用场景的最小构建”；请在业务侧只传入 `http://` / `https://` URI
- 公开头 `aria2/aria2.h` 仍会保留上游 API 面；被裁掉的功能对应 API 在最小构建里会返回失败

### 触发 GitHub Actions

本仓库提供手动触发的发布工作流：`.github/workflows/release.yml`

触发时填写：

- `release_tag`：GitHub Release 标签，例如 `v1.37.0-1`
- `package_version`：写入 `Aria2ConfigVersion.cmake` 的版本号
- `aria2_ref`：`aria2` 的分支或 tag，默认 `master`
- `mile_aria2_ref`：`Mile.Aria2` 的分支或 tag，默认 `main`

工作流会：

1. 拉取上游仓库
2. 分平台构建静态库
3. 生成 zip 包
4. 创建或更新 GitHub Release 并上传产物

### 本地调试脚本

脚本都放在 `scripts/`：

- `scripts/build-unix.sh`
- `scripts/build-windows.ps1`

如果仓库根目录下存在本地 `aria2/` 或 `Mile.Aria2/` git 仓库，脚本会优先从本地仓库克隆临时副本；否则直接从 GitHub 拉取。

示例：

```bash
bash scripts/build-unix.sh linux 1.37.0 .work .dist master
bash scripts/build-unix.sh macos 1.37.0 .work .dist master
```

```powershell
pwsh -File .\scripts\build-windows.ps1 `
  -PackageVersion 1.37.0 `
  -WorkDir .work `
  -OutputDir .dist `
  -MileAria2Ref main
```

### CMake 使用方式

```cmake
set(Aria2_DIR "path/to/package/cmake")
find_package(Aria2 REQUIRED)
target_link_libraries(your_target PRIVATE Aria2::aria2)
```

### 上游项目

- `aria2`: <https://github.com/aria2/aria2>
- `Mile.Aria2`: <https://github.com/ProjectMile/Mile.Aria2>

## English

This repository is only a packaging wrapper. The upstream sources are not committed here. GitHub Actions clones:

- `aria2` for Linux and macOS
- `Mile.Aria2` for Windows MSVC `/MT`

The goal is to produce static library packages oriented to HTTP/HTTPS download scenarios with a consistent layout:

```text
include/
  aria2/
    aria2.h
lib/
  libaria2.a
  aria2.lib
  zlib.lib
cmake/
  Aria2Config.cmake
  Aria2ConfigVersion.cmake
```

### Current trimming scope

The build disables these non-HTTP features that can be trimmed cleanly:

- BitTorrent
- Metalink
- WebSocket
- XML-RPC
- SFTP / libssh2
- SQLite cookie DB
- Expat / libxml2 related paths

Notes:

- The Windows package is built from `Mile.Aria2.Library` and uses the Release `/MT` runtime
- macOS uses native `Apple TLS`
- Linux uses system `OpenSSL + zlib`
- Upstream does not expose a dedicated FTP-disable switch, so this repository targets HTTP/HTTPS-oriented minimal builds; callers should only pass `http://` / `https://` URIs
- The public header `aria2/aria2.h` still exposes the upstream API surface; trimmed features return failure in this minimal build

### Triggering GitHub Actions

The release workflow is defined in `.github/workflows/release.yml`.

Provide these inputs when dispatching it:

- `release_tag`: GitHub Release tag, for example `v1.37.0-1`
- `package_version`: version written into `Aria2ConfigVersion.cmake`
- `aria2_ref`: `aria2` branch or tag, default `master`
- `mile_aria2_ref`: `Mile.Aria2` branch or tag, default `main`

The workflow:

1. Clones upstream repositories
2. Builds static libraries per platform
3. Produces zip packages
4. Creates or updates a GitHub Release and uploads the artifacts

### Local helper scripts

All helper scripts live in `scripts/`:

- `scripts/build-unix.sh`
- `scripts/build-windows.ps1`

If a local `aria2/` or `Mile.Aria2/` git repository exists at the repo root, the scripts clone from that local source first. Otherwise they clone from GitHub.

Examples:

```bash
bash scripts/build-unix.sh linux 1.37.0 .work .dist master
bash scripts/build-unix.sh macos 1.37.0 .work .dist master
```

```powershell
pwsh -File .\scripts\build-windows.ps1 `
  -PackageVersion 1.37.0 `
  -WorkDir .work `
  -OutputDir .dist `
  -MileAria2Ref main
```

### CMake consumption

```cmake
set(Aria2_DIR "path/to/package/cmake")
find_package(Aria2 REQUIRED)
target_link_libraries(your_target PRIVATE Aria2::aria2)
```

### Upstream projects

- `aria2`: <https://github.com/aria2/aria2>
- `Mile.Aria2`: <https://github.com/ProjectMile/Mile.Aria2>
