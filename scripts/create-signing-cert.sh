#!/bin/bash
# 코드서명용 자체 서명(self-signed) 인증서를 login keychain 에 1회 생성한다.
# 목적: 안정적 서명 신원 → 재빌드해도 Keychain "항상 허용"이 유지됨 (ad-hoc 은 빌드마다 무효화).
# 개인키/인증서는 keychain 에만 저장되며 레포에 절대 커밋하지 않는다.
set -euo pipefail

IDENTITY="TokenMac Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# find-identity -v 는 trust 된 것만 보여줌 — self-signed 는 find-certificate 로 확인
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "이미 존재: '$IDENTITY' — 재생성하지 않음 (재생성 시 기존 서명과 불일치)"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# macOS 기본 LibreSSL 사용 — Homebrew OpenSSL 3 의 p12 는 -legacy 없이는 security 가 못 읽음
OPENSSL=/usr/bin/openssl
# p12 전송용 임시 암호 (즉시 import 후 파일 삭제 — 보안 의미 없음, 빈 암호는 MAC 검증 실패 회피용)
P12PW="tokenmac"

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF

echo "==> self-signed 코드서명 인증서 생성"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/openssl.cnf" 2>/dev/null

"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY" -out "$TMP/identity.p12" -passout pass:"$P12PW" 2>/dev/null

echo "==> login keychain 에 import (codesign 사용 허용)"
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12PW" -T /usr/bin/codesign

echo "완료."
security find-certificate -c "$IDENTITY" >/dev/null 2>&1 \
    && echo "'$IDENTITY' 등록 확인됨 (codesign 사용 가능)" \
    || echo "경고: 등록 확인 실패"
echo
echo "다음: ./scripts/build-app.sh 가 이 신원으로 서명합니다."
echo "첫 빌드 시 'codesign 이 키를 사용하려 함' 프롬프트가 1회 뜨면 '항상 허용'을 누르세요."
