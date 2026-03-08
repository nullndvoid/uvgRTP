const std = @import("std");
const c = @cImport(@cInclude("uvgrtp/wrapper_c.h"));

const REMOTE_PORT = 8890;
const LOCAL_PORT = 8891;
const REMOTE_ADDRESS = "127.0.0.1";
const N_TEST_PACKETS = 100;
const PAYLOAD_LEN = 256;

pub fn main(init: std.process.Init) !void {
    const ctx = c.uvgrtp_create_ctx();

    if (ctx == null) {
        return error.InitialisationError;
    }

    defer c.uvgrtp_destroy_ctx(ctx);

    const session = c.uvgrtp_create_session(ctx, REMOTE_ADDRESS);

    if (session == null) {
        return error.InitialisationError;
    }

    defer _ = c.uvgrtp_destroy_session(ctx, session);

    const flags = c.RCE_SEND_ONLY;

    const opus_stream = c.uvgrtp_create_stream(
        session,
        LOCAL_PORT,
        REMOTE_PORT,
        c.RTP_FORMAT_OPUS,
        flags,
    );

    if (opus_stream == null) {
        return error.InitialisationError;
    }

    defer _ = c.uvgrtp_destroy_stream(session, opus_stream);

    const blank_frame = try init.arena.allocator().alloc(u8, PAYLOAD_LEN);
    defer init.arena.allocator().free(blank_frame);

    for (0..N_TEST_PACKETS) |i| {
        @memset(blank_frame, 0x67);

        if (c.uvgrtp_push_frame(
            opus_stream,
            blank_frame.ptr,
            blank_frame.len,
            c.RTP_NO_FLAGS,
        ) != c.RTP_OK) {
            std.log.err("Failed to send RTP frame {d} (rtp_errno={d})", .{ i, c.rtp_errno });
            continue;
        }

        if ((i + 1) % 10 == 0 or i == 0) {
            std.log.info("Sending frame {d}/{d}", .{ i + 1, N_TEST_PACKETS });
        }
    }
}
