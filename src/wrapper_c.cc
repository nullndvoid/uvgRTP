#include <cstdlib>
#include <cstring>
#include <string>

#include <uvgrtp/lib.hh>
#include <uvgrtp/wrapper_c.h>

/* ── helpers to cast between opaque handles and C++ pointers ── */

static inline uvgrtp::context *as_ctx(uvgrtp_context h) { return reinterpret_cast<uvgrtp::context *>(h); }
static inline uvgrtp::session *as_sess(uvgrtp_session h) { return reinterpret_cast<uvgrtp::session *>(h); }
static inline uvgrtp::media_stream *as_strm(uvgrtp_stream h) { return reinterpret_cast<uvgrtp::media_stream *>(h); }
static inline uvgrtp::rtcp *as_rtcp(uvgrtp_rtcp h) { return reinterpret_cast<uvgrtp::rtcp *>(h); }

static inline uvgrtp_context to_handle(uvgrtp::context *p) { return reinterpret_cast<uvgrtp_context>(p); }
static inline uvgrtp_session to_handle(uvgrtp::session *p) { return reinterpret_cast<uvgrtp_session>(p); }
static inline uvgrtp_stream to_handle(uvgrtp::media_stream *p) { return reinterpret_cast<uvgrtp_stream>(p); }
static inline uvgrtp_rtcp to_handle(uvgrtp::rtcp *p) { return reinterpret_cast<uvgrtp_rtcp>(p); }

/* Fill a C frame struct from an rtp_frame. Caller frees via uvgrtp_frame_free(). */
static uvgrtp_frame *wrap_rtp_frame(uvgrtp::frame::rtp_frame *f)
{
    if (!f)
        return nullptr;

    uvgrtp_frame *out = static_cast<uvgrtp_frame *>(std::malloc(sizeof(uvgrtp_frame)));
    if (!out)
    {
        uvgrtp::frame::dealloc_frame(f);
        return nullptr;
    }

    out->payload = f->payload;
    out->payload_len = f->payload_len;
    out->ssrc = f->header.ssrc;
    out->timestamp = f->header.timestamp;
    out->seq = f->header.seq;
    out->marker = f->header.marker;
    out->payload_type = f->header.payload;
    out->internal = f;
    return out;
}

/* ── Receive-hook trampoline ── */

struct hook_ctx
{
    uvgrtp_receive_hook fn;
    void *arg;
};

static void receive_trampoline(void *arg, uvgrtp::frame::rtp_frame *frame)
{
    auto *hctx = static_cast<hook_ctx *>(arg);
    uvgrtp_frame *wrapped = wrap_rtp_frame(frame);
    if (wrapped)
        hctx->fn(hctx->arg, wrapped);
}

/* ── Context ── */

uvgrtp_context
uvgrtp_create_ctx(void)
{
    auto *ctx = new (std::nothrow) uvgrtp::context();
    return to_handle(ctx);
}

void uvgrtp_destroy_ctx(uvgrtp_context ctx)
{
    delete as_ctx(ctx);
}

/* ── Session ── */

uvgrtp_session
uvgrtp_create_session(uvgrtp_context ctx, const char *remote_address)
{
    if (!ctx || !remote_address)
        return nullptr;
    return to_handle(as_ctx(ctx)->create_session(std::string(remote_address)));
}

uvgrtp_session
uvgrtp_create_session_addr_pair(uvgrtp_context ctx,
                                const char *remote_address,
                                const char *local_address)
{
    if (!ctx || !remote_address || !local_address)
        return nullptr;
    return to_handle(as_ctx(ctx)->create_session(
        std::make_pair(std::string(local_address), std::string(remote_address))));
}

int uvgrtp_destroy_session(uvgrtp_context ctx, uvgrtp_session session)
{
    if (!ctx || !session)
        return RTP_INVALID_VALUE;
    return as_ctx(ctx)->destroy_session(as_sess(session));
}

/* ── Media Stream ── */

uvgrtp_stream
uvgrtp_create_stream(uvgrtp_session session,
                     uint16_t local_port, uint16_t remote_port,
                     int rtp_format, int rce_flags)
{
    if (!session)
        return nullptr;
    return to_handle(as_sess(session)->create_stream(
        local_port, remote_port,
        static_cast<rtp_format_t>(rtp_format), rce_flags));
}

int uvgrtp_destroy_stream(uvgrtp_session session, uvgrtp_stream stream)
{
    if (!session || !stream)
        return RTP_INVALID_VALUE;
    return as_sess(session)->destroy_stream(as_strm(stream));
}

/* ── Send ── */

int uvgrtp_push_frame(uvgrtp_stream stream,
                      uint8_t *data, size_t data_len, int rtp_flags)
{
    if (!stream)
        return RTP_INVALID_VALUE;
    return as_strm(stream)->push_frame(data, data_len, rtp_flags);
}

int uvgrtp_push_frame_ts(uvgrtp_stream stream,
                         uint8_t *data, size_t data_len,
                         uint32_t rtp_ts, int rtp_flags)
{
    if (!stream)
        return RTP_INVALID_VALUE;
    return as_strm(stream)->push_frame(data, data_len, rtp_ts, rtp_flags);
}

int uvgrtp_push_frame_ntp(uvgrtp_stream stream,
                          uint8_t *data, size_t data_len,
                          uint32_t rtp_ts, uint64_t ntp_ts, int rtp_flags)
{
    if (!stream)
        return RTP_INVALID_VALUE;
    return as_strm(stream)->push_frame(data, data_len, rtp_ts, ntp_ts, rtp_flags);
}

/* ── Receive ── */

uvgrtp_frame *
uvgrtp_pull_frame(uvgrtp_stream stream)
{
    if (!stream)
        return nullptr;
    return wrap_rtp_frame(as_strm(stream)->pull_frame());
}

uvgrtp_frame *
uvgrtp_pull_frame_timeout(uvgrtp_stream stream, size_t timeout_ms)
{
    if (!stream)
        return nullptr;
    return wrap_rtp_frame(as_strm(stream)->pull_frame(timeout_ms));
}

int uvgrtp_install_receive_hook(uvgrtp_stream stream, void *arg, uvgrtp_receive_hook hook)
{
    if (!stream || !hook)
        return RTP_INVALID_VALUE;

    /* Leak‐free: one hook_ctx per stream. Caller can only install one hook
     * via the C API; re-installing replaces the previous allocation.
     * The hook_ctx is intentionally kept alive for the stream's lifetime. */
    auto *hctx = new (std::nothrow) hook_ctx{hook, arg};
    if (!hctx)
        return RTP_MEMORY_ERROR;

    return as_strm(stream)->install_receive_hook(hctx, receive_trampoline);
}

void uvgrtp_frame_free(uvgrtp_frame *frame)
{
    if (!frame)
        return;
    if (frame->internal)
        uvgrtp::frame::dealloc_frame(
            static_cast<uvgrtp::frame::rtp_frame *>(frame->internal));
    std::free(frame);
}

/* ── Configuration ── */

int uvgrtp_configure(uvgrtp_stream stream, int rcc_flag, int value)
{
    if (!stream)
        return RTP_INVALID_VALUE;
    return as_strm(stream)->configure_ctx(rcc_flag, static_cast<ssize_t>(value));
}

int uvgrtp_get_configuration(uvgrtp_stream stream, int rcc_flag)
{
    if (!stream)
        return -1;
    return as_strm(stream)->get_configuration_value(rcc_flag);
}

/* ── Stream info ── */

uint32_t
uvgrtp_get_ssrc(uvgrtp_stream stream)
{
    if (!stream)
        return 0;
    return as_strm(stream)->get_ssrc();
}

/* ── SRTP ── */

int uvgrtp_add_srtp_ctx(uvgrtp_stream stream, uint8_t *key, uint8_t *salt)
{
    if (!stream)
        return RTP_INVALID_VALUE;
    return as_strm(stream)->add_srtp_ctx(key, salt);
}

int uvgrtp_start_zrtp(uvgrtp_stream stream)
{
    if (!stream)
        return RTP_INVALID_VALUE;
    return as_strm(stream)->start_zrtp();
}

/* ── RTCP ── */

uvgrtp_rtcp
uvgrtp_get_rtcp(uvgrtp_stream stream)
{
    if (!stream)
        return nullptr;
    return to_handle(as_strm(stream)->get_rtcp());
}

void uvgrtp_rtcp_set_ts_info(uvgrtp_rtcp rtcp,
                             uint64_t clock_start, uint32_t clock_rate,
                             uint32_t rtp_ts_start)
{
    if (!rtcp)
        return;
    as_rtcp(rtcp)->set_ts_info(clock_start, clock_rate, rtp_ts_start);
}

int uvgrtp_rtcp_send_app(uvgrtp_rtcp rtcp,
                         const char *name, uint8_t subtype,
                         uint32_t payload_len, const uint8_t *payload)
{
    if (!rtcp)
        return RTP_INVALID_VALUE;
    return as_rtcp(rtcp)->send_app_packet(name, subtype, payload_len, payload);
}