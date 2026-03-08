const std = @import("std");
const uvgRTP = @import("uvgRTP");

const REMOTE_PORT = 8890;
const LOCAL_PORT = 8891;
const REMOTE_ADDRESS = "127.0.0.1";
const N_TEST_PACKETS = 100;
const PAYLOAD_LEN = 256;

pub fn main(init: std.process.Init) !void {
    var ctx = try uvgRTP.Context.init();
    defer ctx.deinit();

    var session = try uvgRTP.Session.init(&ctx, REMOTE_ADDRESS);
    defer session.deinit(&ctx) catch {};

    const stream_flags = uvgRTP.RceFlags{ .send_only = true };
    var opus_stream = try session.createStream(
        LOCAL_PORT,
        REMOTE_PORT,
        .opus,
        stream_flags,
    );
    defer opus_stream.deinit(&session) catch {};

    var blank_frame = try uvgRTP.FrameBuffer.init(init.arena.allocator(), PAYLOAD_LEN);
    defer blank_frame.deinit();

    const rtp_flags = uvgRTP.RtpFlags{};

    for (0..N_TEST_PACKETS) |i| {
        @memset(blank_frame.payload, 0x67);

        opus_stream.pushFrameBuffer(&blank_frame, rtp_flags) catch {
            std.log.err("Failed to send RTP frame {d} (rtp_errno={d})", .{ i, uvgRTP.getUvgRTPErrorNo() });
            continue;
        };

        if ((i + 1) % 10 == 0 or i == 0) {
            std.log.info("Sending frame {d}/{d}", .{ i + 1, N_TEST_PACKETS });
        }
    }
}
