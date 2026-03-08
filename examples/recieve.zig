const std = @import("std");
const c = @cImport(@cInclude("uvgrtp/wrapper_c.h"));

const REMOTE_PORT = 8891;
const LOCAL_PORT = 8890;
const REMOTE_ADDRESS = "127.0.0.1";
const N_TEST_PACKETS = 100;

pub fn main() !void {
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

    const flags = c.RCE_RECEIVE_ONLY;

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

    var recieved: u8 = 0;
    while (recieved < N_TEST_PACKETS) {
        const frame = c.uvgrtp_pull_frame(opus_stream);
        defer c.uvgrtp_frame_free(frame);

        if (frame == null) {
            std.log.err(
                "uvgrtp_pull_frame failed (rtp_errno={d})",
                .{c.rtp_errno},
            );

            continue;
        }

        recieved += 1;

        std.log.info(
            "Recieved frame {d}/{d}, payload_len = {d}",
            .{ recieved, N_TEST_PACKETS, frame.*.payload_len },
        );
    }
}
