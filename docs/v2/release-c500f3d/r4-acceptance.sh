#!/usr/bin/env bash
# r4-acceptance.sh —— R4 集成候选的宿主编排（Windows Git Bash + Docker Desktop）。
#
# 做的事：
#   1) 用 `git -c core.autocrlf=false archive` 把四棵树按 LF 展开到临时目录：
#        base  = 生产发布线 v2（3e8e15f1，无门面 / 无身份）
#        prev  = R3 判定代码（6add3a6，有身份 / 无门面）
#        r4    = 本轮集成树（默认 HEAD，可用 R4_TREE_REF 指定已由 git write-tree 固定的树对象）
#        r3base= R3 的旧工具基线（9654540，用于 RED 复现）
#      /ai/ 的静态树取自 PR #34（web/ai，10 个文件），/ming/ 用夹具。
#   2) 起 node:20（= v20.20.2）与 nginx:1.18.0 两个容器（独立网络，只把 1428x 发到 127.0.0.1）。
#   3) 在 node 容器里跑 r4-acceptance-inner.sh：12 项经 nginx 的验收 + 四个切流场景 + R3 四套装置 + 首页回归。
#   4) 收日志、拆容器。退出码 = 内层失败项数。
#
# 用法：
#   bash docs/v2/release-c500f3d/r4-acceptance.sh
#   R4_TREE_REF=$(git write-tree) bash docs/v2/release-c500f3d/r4-acceptance.sh
#
# 不写生产、不 reload nginx、不碰其他 worktree / 容器；容器与网络名带本轮时间戳，只删自己的。
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd) || exit 1
cd "$REPO" || exit 1

BASE_REF=${BASE_REF:-3e8e15f17bc5bae7fe78298661a5d5d14ce581c6}
PREV_REF=${PREV_REF:-6add3a6da178bf36962249300926d0656ee2b66b}
R3BASE_REF=${R3BASE_REF:-9654540d129d0b12cd07591855ee42bf9a6dad79}
AI_REF=${AI_REF:-055609ab4c134077b684143b59b9bf74b6463388}
R4_TREE_REF=${R4_TREE_REF:-HEAD}

STAMP=$(date +%Y%m%d-%H%M%S)
TMPBASE=$(cygpath -m "${LOCALAPPDATA:-$HOME/AppData/Local}") || exit 1
WORK="$TMPBASE/r4-accept-$STAMP"
TREES="$WORK/trees"; STATIC="$WORK/static"; NGXDIR="$WORK/nginx"; LOGS="$WORK/logs"; MANI="$WORK/manifests"
NET="ws-r4-net-$STAMP"; NODE_CT="ws-r4-node-$STAMP"; NGX_CT="ws-r4-nginx-$STAMP"
mkdir -p "$TREES"/{base,prev,r4,r3base} "$STATIC"/{ai,ming} "$NGXDIR/snippets" "$LOGS" "$MANI" "$WORK/scripts" || exit 1

say() { printf '\n### %s\n' "$*"; }
die() { printf '\nFAIL %s\n' "$*" >&2; exit 1; }

cleanup() {
  docker logs "$NGX_CT" > "$LOGS/nginx.log" 2>&1 || true
  docker rm -f "$NGX_CT" >/dev/null 2>&1 || true
  docker rm -f "$NODE_CT" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
}
trap cleanup EXIT

say "0) 环境自检"
command -v docker >/dev/null || die "没有 docker"
docker version --format '{{.Server.Version}}' >/dev/null 2>&1 || die "docker 引擎不可用"
docker image inspect node:20 >/dev/null 2>&1 || die "缺镜像 node:20（= v20.20.2）"
docker image inspect nginx:1.18.0 >/dev/null 2>&1 || die "缺镜像 nginx:1.18.0"
NODE_VER=$(MSYS_NO_PATHCONV=1 docker run --rm node:20 node -v | tr -d '\r')
NGX_VER=$(MSYS_NO_PATHCONV=1 docker run --rm nginx:1.18.0 nginx -v 2>&1 | tr -d '\r')
echo "node 容器版本：$NODE_VER"
echo "nginx 容器版本：$NGX_VER"
echo "工作目录：$WORK"

say "1) 展开四棵树（LF；不经过工作副本）"
extract() { # extract <ref> <dest>
  git -c core.autocrlf=false archive "$1" | tar -xf - -C "$2" \
    || die "git archive $1 失败"
}
crinfo() { # crinfo <dir> <label> —— 只报数不判红：仓库里本来就有 CRLF blob，逐字节身份按 blob 字节算
  local n; n=$(LC_ALL=C grep -rlI $'\r' "$1" 2>/dev/null | wc -l | tr -d ' ')
  echo "  $2 含 CR 的文件=$n（blob 原样；由内层 tree round-trip 证明展开无损）"
}
extract "$BASE_REF" "$TREES/base";   crinfo "$TREES/base" base
extract "$PREV_REF" "$TREES/prev";   crinfo "$TREES/prev" prev
extract "$R4_TREE_REF" "$TREES/r4";  crinfo "$TREES/r4" r4
extract "$R3BASE_REF" "$TREES/r3base"; crinfo "$TREES/r3base" r3base

TREE_BASE=$(git rev-parse "$BASE_REF^{tree}")
TREE_PREV=$(git rev-parse "$PREV_REF^{tree}")
TREE_R4=$(git rev-parse "$R4_TREE_REF^{tree}")
echo "  tree base=$TREE_BASE"
echo "  tree prev=$TREE_PREV"
echo "  tree r4  =$TREE_R4"
# 容器里合成的提交在 Windows 绑定挂载上会丢掉 exec 位（整棵 tree 号必然不同）。
# 发布身份只认内容字节，所以给容器一份"blob 内容+路径"清单，让它证明导入的内容逐条无损。
for pair in "base:$BASE_REF" "prev:$PREV_REF" "r4:$R4_TREE_REF"; do
  n=${pair%%:*}; ref=${pair#*:}
  git ls-tree -r --format='%(objectname) %(path)' "$ref" | LC_ALL=C sort > "$MANI/$n.lst" \
    || die "生成 $n 清单失败"
  echo "  manifest $n: $(wc -l < "$MANI/$n.lst" | tr -d ' ') 个文件，sha256=$(sha256sum < "$MANI/$n.lst" | cut -d' ' -f1)"
done

say "2) 独立复算集成树身份（与运行进程无关；宿主 node 与容器 node20 各算一次）"
ID_R4=$(node "$TREES/r4/docs/v2/release-c500f3d/release-id.mjs" "$TREES/r4") \
  || die "宿主算不出集成树身份"
printf '%s' "$ID_R4" | grep -Eq '^[0-9a-f]{64}$' || die "身份形状不对：$ID_R4"
echo "  EXPECT_RELEASE_ID=$ID_R4"
ID_PREV=$(node "$TREES/r4/docs/v2/release-c500f3d/release-id.mjs" "$TREES/prev") || die "prev 身份算不出"
ID_BASE=$(node "$TREES/r4/docs/v2/release-c500f3d/release-id.mjs" "$TREES/base") || die "base 身份算不出"
echo "  prev 身份=$ID_PREV（应等于 R3 的 6add3a6 树）"
echo "  base 身份=$ID_BASE（生产 v2 基线）"
[ "$ID_R4" != "$ID_PREV" ] || die "集成树身份与 prev 相同（没重新计算 / 没真正集成）"

say "3) /ai/ 静态树（PR #34 的 web/ai，10 个文件）与 /ming/ 夹具"
mkdir -p "$WORK/_ai"
git -c core.autocrlf=false archive "$AI_REF" web/ai | tar -xf - -C "$WORK/_ai" || die "取 web/ai 失败"
cp -a "$WORK/_ai/web/ai/." "$STATIC/ai/" || die "拷 web/ai 失败"
rm -rf "$WORK/_ai"
AI_N=$(find "$STATIC/ai" -type f | wc -l | tr -d ' ')
[ "$AI_N" = "10" ] || die "web/ai 文件数 = $AI_N（期望 10）"
AI_TREE=$(git rev-parse "$AI_REF:web/ai")
echo "  web/ai 树=$AI_TREE 文件=$AI_N"
cat > "$STATIC/ming/index.html" <<'EOF'
<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><title>MING-FIXTURE-R4</title></head>
<body><h1>MING-FIXTURE-R4</h1><p>静态作品集夹具：只用于证明 /ming/ 在集成候选下不被应用路由影响。</p></body></html>
EOF

say "4) nginx 1.18 配置（生产片段原样；只有 upstream 与静态根换成夹具）"
cp docs/v2/release-c500f3d/ai-route-harness/ming-portfolio.conf "$NGXDIR/snippets/ming-portfolio.conf" \
  || die "取 ming-portfolio.conf 失败"
cat > "$NGXDIR/nginx.conf" <<'EOF'
worker_processes 1;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events { worker_connections 64; }

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    access_log /var/log/nginx/access.log;
    sendfile on;
    keepalive_timeout 65;

    upstream world_space_node {
        server @@UPSTREAM@@:3200 max_fails=0;
        keepalive 8;
    }

    server {
        listen 8080;
        server_name ymai.fun;
        client_max_body_size 64k;

        include /etc/nginx/snippets/ming-portfolio.conf;
        location / {
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header Connection "";
            proxy_connect_timeout 5s;
            proxy_read_timeout 180s;
            proxy_send_timeout 180s;
            proxy_pass http://world_space_node;
        }
    }
}
EOF
sed -i "s/@@UPSTREAM@@/$NODE_CT/" "$NGXDIR/nginx.conf"
grep -q "$NODE_CT:3200" "$NGXDIR/nginx.conf" || die "nginx.conf upstream 没替换成功"

cp docs/v2/release-c500f3d/r4-acceptance-inner.sh "$WORK/scripts/" || die "复制内层脚本失败"

PORT=""
for p in $(seq 14280 14299); do
  netstat -ano 2>/dev/null | grep -q ":$p " || { PORT=$p; break; }
done
[ -n "$PORT" ] || die "14280-14299 都被占用"

say "5) 起容器（独立网络；只发布 127.0.0.1:$PORT）"
docker network create "$NET" >/dev/null || die "建网络失败"
MSYS_NO_PATHCONV=1 docker run -d --name "$NODE_CT" --network "$NET" -v "$WORK:/srv" -w /srv node:20 sleep infinity >/dev/null \
  || die "起 node 容器失败"
MSYS_NO_PATHCONV=1 docker run -d --name "$NGX_CT" --network "$NET" \
  -v "$WORK/nginx/nginx.conf:/etc/nginx/nginx.conf:ro" \
  -v "$WORK/nginx/snippets:/etc/nginx/snippets:ro" \
  -v "$WORK/static:/srv/static:ro" \
  -p "127.0.0.1:$PORT:8080" nginx:1.18.0 >/dev/null || die "起 nginx 容器失败"
echo "  node=$NODE_CT nginx=$NGX_CT net=$NET port=$PORT"

for i in $(seq 1 60); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "http://127.0.0.1:$PORT/healthz" 2>/dev/null || true)
  [ "$CODE" != "000" ] && [ -n "$CODE" ] && break
  sleep 0.25
done
[ "${CODE:-000}" != "000" ] || die "nginx 没起来（最后一次 code=${CODE:-none}）"
echo "  nginx 已转发（/healthz 当前 code=$CODE；应用还没起，502/503 属正常）"

say "6) 容器内跑 R4 验收"
MSYS_NO_PATHCONV=1 docker exec \
  -e NGINX_HOST="$NGX_CT" \
  -e R4_SHA="$R4_TREE_REF" -e PREV_SHA="$PREV_REF" -e BASE_SHA="$BASE_REF" \
  -e EXPECT_RELEASE_ID="$ID_R4" \
  "$NODE_CT" bash /srv/scripts/r4-acceptance-inner.sh 2>&1 | tee "$LOGS/r4-acceptance.log"
RC=${PIPESTATUS[0]}

say "7) 收日志"
cp "$WORK/work/root/run/app.log" "$LOGS/app.log" 2>/dev/null || true
mkdir -p "$LOGS/scenes"
cp "$WORK"/work/body/*.log "$LOGS/scenes/" 2>/dev/null || true
cp "$WORK/work/root/state/"cutover-*.txt "$LOGS/scenes/" 2>/dev/null || true
docker logs "$NGX_CT" > "$LOGS/nginx.log" 2>&1 || true
cat > "$LOGS/summary.txt" <<EOF
stamp=$STAMP
node_container=$NODE_VER
nginx_container=$NGX_VER
r4_ref=$R4_TREE_REF
tree_r4=$TREE_R4
tree_prev=$TREE_PREV
tree_base=$TREE_BASE
expected_release_id=$ID_R4
prev_release_id=$ID_PREV
base_release_id=$ID_BASE
ai_tree=$AI_TREE
inner_exit=$RC
EOF
echo "日志：$LOGS"
echo "结论行：$(grep -E '^R4_ACCEPTANCE' "$LOGS/r4-acceptance.log" | tail -2 | tr '\n' ' ')"

[ "$RC" -eq 0 ] && echo "R4_HOST_ACCEPTANCE=PASS" || echo "R4_HOST_ACCEPTANCE=FAIL"
exit "$RC"
