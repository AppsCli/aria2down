#!/usr/bin/env bash
# 将 Native Messaging 宿主清单安装到用户目录（Chrome / Chromium）。
# 用法：EXTENSION_ID=your_extension_id ./scripts/install_native_messaging_host.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT_ID="${EXTENSION_ID:-}"

if [[ -z "${EXT_ID}" ]]; then
  echo "请设置环境变量 EXTENSION_ID（Chrome 扩展 ID）" >&2
  exit 1
fi

HOST_SH="${ROOT}/extensions/native-messaging/host.sh"
TEMPLATE="${ROOT}/extensions/native-messaging/com.aria2down.host.json"
DEST_DIR="${HOME}/Library/Application Support/Google/Chrome/NativeMessagingHosts"

if [[ "$(uname -s)" == "Linux" ]]; then
  DEST_DIR="${HOME}/.config/google-chrome/NativeMessagingHosts"
fi

mkdir -p "${DEST_DIR}"
chmod +x "${HOST_SH}"

python3 - <<PY
import json, os
tpl = json.load(open("${TEMPLATE}"))
tpl["path"] = "${HOST_SH}"
tpl["allowed_origins"] = [f"chrome-extension://${EXT_ID}/"]
out = os.path.join("${DEST_DIR}", "com.aria2down.host.json")
json.dump(tpl, open(out, "w"), indent=2)
print("Wrote", out)
PY

echo "Done. Restart Chrome and load the unpacked extension."
