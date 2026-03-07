#ifndef UVGRTP_H
#define UVGRTP_H

#include <stdint.h>
#include <stddef.h>
#include <uvgrtp/util.hh>

#ifdef __cplusplus
extern "C"
{
#endif

    /* Opaque handle types for type safety */
    typedef struct uvgrtp_context_handle *uvgrtp_context;
    typedef struct uvgrtp_session_handle *uvgrtp_session;
    typedef struct uvgrtp_stream_handle *uvgrtp_stream;
    typedef struct uvgrtp_rtcp_handle *uvgrtp_rtcp;

    /* C-compatible RTP frame returned by pull_frame */
    typedef struct uvgrtp_frame
    {
        uint8_t *payload;
        size_t payload_len;
        uint32_t ssrc;
        uint32_t timestamp;
        uint16_t seq;
        uint8_t marker;
        uint8_t payload_type;
        void *internal; /* internal pointer for deallocation, do not touch */
    } uvgrtp_frame;

    /* Receive hook callback type */
    typedef void (*uvgrtp_receive_hook)(void *arg, uvgrtp_frame *frame);

    /* ── Context ── */

    uvgrtp_context uvgrtp_create_ctx(void);
    void uvgrtp_destroy_ctx(uvgrtp_context ctx);

    /* ── Session ── */

    uvgrtp_session uvgrtp_create_session(uvgrtp_context ctx, const char *remote_address);
    uvgrtp_session uvgrtp_create_session_addr_pair(uvgrtp_context ctx,
                                                   const char *remote_address,
                                                   const char *local_address);
    int uvgrtp_destroy_session(uvgrtp_context ctx, uvgrtp_session session);

    /* ── Media Stream ── */

    uvgrtp_stream uvgrtp_create_stream(uvgrtp_session session,
                                       uint16_t local_port, uint16_t remote_port,
                                       int rtp_format, int rce_flags);
    int uvgrtp_destroy_stream(uvgrtp_session session, uvgrtp_stream stream);

    /* ── Send ── */

    int uvgrtp_push_frame(uvgrtp_stream stream,
                          uint8_t *data, size_t data_len, int rtp_flags);

    int uvgrtp_push_frame_ts(uvgrtp_stream stream,
                             uint8_t *data, size_t data_len,
                             uint32_t rtp_ts, int rtp_flags);

    int uvgrtp_push_frame_ntp(uvgrtp_stream stream,
                              uint8_t *data, size_t data_len,
                              uint32_t rtp_ts, uint64_t ntp_ts, int rtp_flags);

    /* ── Receive ── */

    /* Blocking pull; returns NULL on error. Caller must call uvgrtp_frame_free(). */
    uvgrtp_frame *uvgrtp_pull_frame(uvgrtp_stream stream);

    /* Pull with timeout in milliseconds; returns NULL if timed out or error. */
    uvgrtp_frame *uvgrtp_pull_frame_timeout(uvgrtp_stream stream, size_t timeout_ms);

    /* Install async receive hook. arg is passed through to the callback. */
    int uvgrtp_install_receive_hook(uvgrtp_stream stream, void *arg, uvgrtp_receive_hook hook);

    /* Free a frame obtained from pull_frame or received via hook */
    void uvgrtp_frame_free(uvgrtp_frame *frame);

    /* ── Configuration ── */

    int uvgrtp_configure(uvgrtp_stream stream, int rcc_flag, int value);
    int uvgrtp_get_configuration(uvgrtp_stream stream, int rcc_flag);

    /* ── Stream info ── */

    uint32_t uvgrtp_get_ssrc(uvgrtp_stream stream);

    /* ── SRTP ── */

    int uvgrtp_add_srtp_ctx(uvgrtp_stream stream, uint8_t *key, uint8_t *salt);
    int uvgrtp_start_zrtp(uvgrtp_stream stream);

    /* ── RTCP ── */

    uvgrtp_rtcp uvgrtp_get_rtcp(uvgrtp_stream stream);
    void uvgrtp_rtcp_set_ts_info(uvgrtp_rtcp rtcp,
                                 uint64_t clock_start, uint32_t clock_rate,
                                 uint32_t rtp_ts_start);
    int uvgrtp_rtcp_send_app(uvgrtp_rtcp rtcp,
                             const char *name, uint8_t subtype,
                             uint32_t payload_len, const uint8_t *payload);

#ifdef __cplusplus
}
#endif

#endif /* UVGRTP_H */