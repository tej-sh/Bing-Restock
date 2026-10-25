#!/bin/bash
URL="https://rewards.bing.com/redeem/sku/000885000034"
mkdir -p state

for i in 1 2 3; do
  resp=$(curl -sL -A "Mozilla/5.0" -H "Accept-Language: en-IN,en;q=0.9" -H "Cookie: $BING_COOKIE" -w $'\n%{http_code}' "$URL")
  code=${resp##*$'\n'}
  [ "$code" = 200 ] && break
  sleep 10
done
html=${resp%$'\n'*}
size=${#html}

if [ "$code" != 200 ]; then
  echo "fetch failed http=$code, keeping state"
  exit 0
fi

if ! grep -q "Flipkart Gift Card" <<<"$html"; then
  state=unknown
elif grep -q "we&#x27;re restocking" <<<"$html"; then
  state=restocking
else
  state=available
fi

now=$(TZ=Asia/Kolkata date '+%d %b %Y, %I:%M:%S %p IST')
prev=$(cat state/hash 2>/dev/null)
msg="state=$state prev=${prev:-none} time=$now http=$code size=$size cookie_len=${#BING_COOKIE}"
echo "$msg"

if [ "$state" != "$prev" ]; then
  if [ -z "$NTFY_TOPIC" ]; then
    echo "ERROR: NTFY_TOPIC is empty"
  else
    pri=default
    [ "$state" = available ] && pri=urgent
    [ "$state" = unknown ] && pri=high
    [ "$state" = restocking ] && pri=min

    out=$(curl -sS -w ' [ntfy http=%{http_code}]' \
      -H "Priority: $pri" -H "Title: bing-watch $state ($now)" \
      -d "$msg" "https://ntfy.sh/$NTFY_TOPIC" 2>&1)
    echo "ntfy: $out"

    printf '%s' "$html" > /tmp/page.html
    out=$(curl -sS -T /tmp/page.html \
      -H "Priority: $pri" \
      -H "Filename: page-$state.html" \
      -H "Title: bing-watch page ($state)" \
      -w ' [ntfy http=%{http_code}]' "https://ntfy.sh/$NTFY_TOPIC" 2>&1)
    echo "ntfy file: $out"
  fi
fi

echo "$state" > state/hash
