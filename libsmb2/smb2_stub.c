#include <stddef.h>
#include <stdint.h>
#include <time.h>
/* NOTE: smb2.h를 libsmb2.h보다 먼저 포함해야 한다 — libsmb2.h가 smb2.h의 타입(SMB2_GUID_SIZE 등)을
 * 쓰는데, libsmb2.h는 stdint.h/time.h를 스스로 포함하지 않는다 (libsmb2 예제도 smb2.h를 먼저 포함). */
#include <smb2/smb2.h>
#include <smb2/libsmb2.h>

/*
 * WHY: libsmb2.so(LGPL 분리 공유 라이브러리) 내부에서 컨텍스트 생성 및
 * §3.1 서명 기본 활성화(SMB2_NEGOTIATE_SIGNING_ENABLED)를 수행하는 심볼.
 */
struct smb2_context *smb2_hp_create_signed_context(void) {
    struct smb2_context * const ctx = smb2_init_context();
    if (ctx == NULL) {
        return NULL;
    }
    smb2_set_security_mode(ctx, SMB2_NEGOTIATE_SIGNING_ENABLED);
    smb2_set_timeout(ctx, 15);
    return ctx;
}
